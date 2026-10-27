use crate::{
    dev::{
        app_groups::{AppGroup, AppGroupsApi},
        app_ids::{AppId, AppIdsApi, Profile},
        developer_session::DeveloperSession,
        devices::DevicesApi,
        teams::{DeveloperTeam, TeamsApi},
    },
    sideload::{
        TeamSelection,
        application::{Application, SpecialApp},
        builder::{ExtensionsBehaviorSelection, MaxCertsBehavior},
        cert_identity::CertificateIdentity,
        healthkit::{self, RepairTarget},
        sign,
    },
    util::{
        callbacks::{ExtensionsBehaviorCallback, MaxCertsCallback},
        device::IdeviceInfo,
        storage::SideloadingStorage,
    },
};

use std::path::PathBuf;

use idevice::provider::IdeviceProvider;
use plist::Dictionary;
use rootcause::{option_ext::OptionExt, prelude::*};
use tracing::info;

pub struct Sideloader<C: MaxCertsCallback, E: ExtensionsBehaviorCallback> {
    team_selection: TeamSelection,
    storage: Box<dyn SideloadingStorage>,
    dev_session: DeveloperSession,
    machine_name: String,
    apple_email: String,
    max_certs_behavior: MaxCertsBehavior<C>,
    extensions_behavior: ExtensionsBehaviorSelection<E>,
    delete_app_after_install: bool,
    team: Option<DeveloperTeam>,
}

struct PreparedLuqmaRepair {
    target: RepairTarget,
    app_id: AppId,
    app_group: AppGroup,
}

impl<C: MaxCertsCallback, E: ExtensionsBehaviorCallback> Sideloader<C, E> {
    /// Construct a new `Sideloader` instance with the provided configuration
    ///
    /// See [`crate::sideload::SideloaderBuilder`] for more details and a more convenient way to construct a `Sideloader`.
    pub fn new(
        dev_session: DeveloperSession,
        apple_email: String,
        team_selection: TeamSelection,
        max_certs_behavior: MaxCertsBehavior<C>,
        machine_name: String,
        storage: Box<dyn SideloadingStorage>,
        extensions_behavior: ExtensionsBehaviorSelection<E>,
        delete_app_after_install: bool,
    ) -> Self {
        Sideloader {
            team_selection,
            storage,
            dev_session,
            machine_name,
            apple_email,
            max_certs_behavior,
            extensions_behavior,
            delete_app_after_install,
            team: None,
        }
    }

    /// Sign the app at the provided path and return the path to the signed app bundle (in a temp dir). To sign and install, see [`Self::install_app`].
    /// `pairing_file` is the optional pairing file to be encrypted and placed in the bundle if installing AltStore.
    /// `device_udid` is the optional device UDID to be used for AltStore pairing file injection.
    pub async fn sign_app<F, Fut>(
        &mut self,
        app_path: PathBuf,
        team: Option<DeveloperTeam>,
        // this will be replaced with proper entitlement handling later
        increased_memory_limit: bool,
        progress_callback: Option<F>,
        pairing_file: Option<&[u8]>,
        device_udid: Option<&str>,
    ) -> Result<(PathBuf, Option<SpecialApp>), Report>
    where
        F: Fn(f32) -> Fut,
        Fut: Future<Output = ()>,
    {
        healthkit::validate_repair_options(increased_memory_limit)?;
        let app = Application::new(app_path)?;
        let team = match team {
            Some(t) => t,
            None => self.get_team().await?,
        };
        let prepared = self.prepare_luqma_repair(&app, &team, device_udid).await?;
        self.sign_prepared_luqma(app, team, prepared, increased_memory_limit,
                                 progress_callback, pairing_file).await
    }

    /// The dedicated repair never falls back to generic App ID/device/group
    /// registration. Every call here is read-only and runs before certificate
    /// retrieval or capability changes.
    async fn prepare_luqma_repair(
        &mut self,
        app: &Application,
        team: &DeveloperTeam,
        device_udid: Option<&str>,
    ) -> Result<PreparedLuqmaRepair, Report> {
        let has_nested = !app.bundle.app_extensions().is_empty() ||
            ["PlugIns", "Watch", "AppClips"].iter().any(|name| {
                isideload_vfs::fs::metadata(app.bundle.bundle_dir.join(name)).is_ok()
            });
        let target = healthkit::repair_target(&app.bundle.app_info, &team.team_id,
                                            has_nested, device_udid)?;
        let ids = self.dev_session.list_app_ids(team, None).await
            .map_err(|_| report!("Could not verify Luqma's existing App ID. No account registrations were attempted."))?;
        let app_id = healthkit::existing_app_id(&ids.app_ids, &target)?;
        let devices = self.dev_session.list_devices(team, None).await
            .map_err(|_| report!("Could not verify the existing registered iPhone. No device was added."))?;
        healthkit::registered_device(&devices, &target)?;
        let groups = self.dev_session.list_app_groups(team, None).await
            .map_err(|_| report!("Could not verify Luqma's existing App Group. No group was added."))?;
        let app_group = healthkit::existing_app_group(&groups, &target)?;
        Ok(PreparedLuqmaRepair { target, app_id, app_group })
    }

    async fn sign_prepared_luqma<F, Fut>(
        &mut self,
        mut app: Application,
        team: DeveloperTeam,
        prepared: PreparedLuqmaRepair,
        increased_memory_limit: bool,
        progress_callback: Option<F>,
        _pairing_file: Option<&[u8]>,
    ) -> Result<(PathBuf, Option<SpecialApp>), Report>
    where
        F: Fn(f32) -> Fut,
        Fut: Future<Output = ()>,
    {
        let PreparedLuqmaRepair { target, mut app_id, app_group } = prepared;
        // A new Apple-issued development certificate may be requested if this
        // separate signer's key has none. Never revoke another tool's certificate.
        let no_revocation: MaxCertsBehavior<C> = MaxCertsBehavior::Error;
        let cert_identity = CertificateIdentity::retrieve(
            &self.machine_name, &self.apple_email, &mut self.dev_session, &team,
            self.storage.as_ref(), &no_revocation,
        ).await.map_err(|_| report!("Could not obtain an authorized signing certificate without revocation. No existing certificate was revoked."))?;
        if let Some(callback) = &progress_callback { callback(0.1).await; }

        app.update_bundle_id(healthkit::ORIGINAL_BUNDLE_ID, &target.bundle_id)?;
        app_id.ensure_group_feature(&mut self.dev_session, &team).await
            .map_err(|_| report!("Apple could not configure Luqma's existing App Group. Installation was stopped."))?;
        self.dev_session.assign_app_group(&team, &app_group, &app_id, None).await
            .map_err(|_| report!("Apple could not associate Luqma's existing App Group. Installation was stopped."))?;
        if increased_memory_limit {
            self.dev_session.add_increased_memory_limit(&team, &app_id).await
                .map_err(|_| report!("Apple could not configure the requested memory capability. Installation was stopped."))?;
        }
        // Configure Health last, preserving Apple's current feature allowlist.
        // The helper requires a successful Apple response and Boolean true.
        app_id.ensure_healthkit_feature(&mut self.dev_session, &team).await?;
        if let Some(callback) = &progress_callback { callback(0.15).await; }

        let main_provisioning_profile = healthkit::download_profile(
            &mut self.dev_session, &team, &app_id,
        ).await?;
        // A feature-toggle reply is insufficient: validate the actual unchanged
        // downloaded CMS profile before any signing or device installation.
        healthkit::validate_downloaded_profile(
            main_provisioning_profile.encoded_profile.as_ref(), &team.team_id,
            &target, &cert_identity,
        )?;
        if let Some(callback) = &progress_callback { callback(0.2).await; }

        app.bundle.write_info()?;
        for framework in app.bundle.frameworks_mut() { framework.write_info()?; }
        let mut no_extension_profiles: Vec<(String, Profile, Dictionary)> = Vec::new();
        // sign::sign takes claims and embedded.mobileprovision from this same
        // Apple response. Do not insert HealthKit into an unauthorized profile
        // or substitute a locally manufactured profile/entitlement set.
        sign::sign(&mut app, &cert_identity, &main_provisioning_profile,
                   &mut no_extension_profiles, &None, &team, progress_callback)
            .await.map_err(|_| report!("The authorized Luqma application could not be signed. Installation was stopped."))?;
        info!("Luqma signed using Apple's returned HealthKit-enabled profile; physical consent and reads still require device verification.");
        Ok((app.bundle.bundle_dir.clone(), None))
    }

    #[cfg(feature = "install")]
    /// Repair only the original Luqma IPA for an already registered iPhone.
    /// Missing App IDs, devices or groups fail before account mutations; this
    /// dedicated path never creates registrations, revokes certificates, or
    /// configures Watch devices. A successful install is not Health read consent.
    pub async fn install_app<F, Fut>(
        &mut self,
        device_provider: &impl IdeviceProvider,
        app_path: PathBuf,
        increased_memory_limit: bool,
        progress_callback: Option<F>,
        pairing_file: Option<&[u8]>,
    ) -> Result<Option<SpecialApp>, Report>
    where
        F: Fn(f32) -> Fut,
        Fut: Future<Output = ()>,
    {
        healthkit::validate_repair_options(increased_memory_limit)?;
        let app = Application::new(app_path)?;
        let device_info = IdeviceInfo::from_device(device_provider).await?;
        let team = self.get_team().await?;
        let prepared = self.prepare_luqma_repair(&app, &team, Some(&device_info.udid)).await?;
        let (signed_app_path, special_app) = self.sign_prepared_luqma(
            app, team, prepared, increased_memory_limit, progress_callback, pairing_file,
        ).await?;

        info!("Transferring authorized Luqma application...");
        let last_logged_progress = std::sync::Arc::new(std::sync::Mutex::new(0));
        crate::sideload::install::install_app(device_provider, &signed_app_path, |progress| {
            let mut last_progress = last_logged_progress.lock().unwrap();
            if progress >= *last_progress + 10 {
                *last_progress = progress;
                info!("Installing: {}%", progress);
            }
        }).await.context("The iPhone did not accept the signed Luqma installation")?;
        if self.delete_app_after_install &&
            isideload_vfs::fs::remove_dir_all(&signed_app_path).is_err() {
            tracing::warn!("Could not remove the temporary signed app directory.");
        }
        Ok(special_app)
    }

    /// Get the developer team according to the configured team selection behavior
    pub async fn get_team(&mut self) -> Result<DeveloperTeam, Report> {
        if let Some(team) = &self.team {
            return Ok(team.clone());
        }
        let teams = self.dev_session.list_teams().await?;
        let team = match teams.len() {
            0 => {
                bail!("No developer teams available")
            }
            1 => teams.into_iter().next().ok_or_report()?,
            _ => {
                info!(
                    "Multiple developer teams found, {} as per configuration",
                    self.team_selection
                );
                match &self.team_selection {
                    TeamSelection::First => teams.into_iter().next().ok_or_report()?,
                    TeamSelection::PromptOnce(prompt_fn)
                    | TeamSelection::PromptAlways(prompt_fn) => {
                        let selection =
                            prompt_fn(&teams).ok_or_else(|| report!("No team selected"))?;
                        teams
                            .into_iter()
                            .find(|t| t.team_id == selection)
                            .ok_or_else(|| report!("No team found with ID {}", selection))?
                    }
                }
            }
        };
        if !matches!(&self.team_selection, TeamSelection::PromptAlways(_)) {
            self.team = Some(team.clone());
        }
        Ok(team)
    }

    pub fn get_dev_session(&mut self) -> &mut DeveloperSession {
        &mut self.dev_session
    }

    pub fn get_email(&self) -> &str {
        &self.apple_email
    }
}
