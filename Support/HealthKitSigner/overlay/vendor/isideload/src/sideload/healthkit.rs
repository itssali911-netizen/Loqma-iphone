//! Narrow, fail-closed Luqma repair checks. This module never registers an App ID,
//! device, or group, and never changes a profile or invents signing entitlements.
//! CMS parsing is metadata inspection, not verification of Apple's CMS signature;
//! the target iPhone remains the final signature/provisioning enforcement authority.

use std::time::{SystemTime, UNIX_EPOCH};

use apple_codesign_quick::ProvisioningProfile;
use plist::{Dictionary, Value};
use rootcause::prelude::*;
use x509_cert::der::Encode;

use crate::dev::{app_groups::AppGroup, app_ids::AppId, devices::DeveloperDevice};
use crate::sideload::cert_identity::CertificateIdentity;

pub(crate) const ORIGINAL_BUNDLE_ID: &str = "app.luqma.diary";
const HEALTHKIT: &str = "com.apple.developer.healthkit";

pub(crate) struct RepairTarget {
    pub bundle_id: String,
    pub group_identifier: String,
    pub device_udid: String,
}

pub(crate) fn validate_repair_options(increased_memory_limit: bool) -> Result<(), Report> {
    if increased_memory_limit {
        bail!("This dedicated repair only configures Luqma HealthKit. Unrelated memory capabilities are not supported.");
    }
    Ok(())
}

/// Pure preflight, before account mutations or certificate retrieval. An already
/// rewritten IPA must not silently create a double-suffixed App ID.
pub(crate) fn repair_target(
    info: &Dictionary,
    team: &str,
    has_nested_apps: bool,
    device_udid: Option<&str>,
) -> Result<RepairTarget, Report> {
    if info.get("CFBundleIdentifier").and_then(Value::as_string) != Some(ORIGINAL_BUNDLE_ID) {
        bail!("This repair accepts only the original app.luqma.diary IPA. Already re-signed identifiers and other apps are not supported; no new App ID was registered.");
    }
    if !info.get("CFBundleSupportedPlatforms").and_then(Value::as_array).is_some_and(|platforms| {
        platforms.len() == 1 && platforms[0].as_string() == Some("iPhoneOS")
    }) {
        bail!("This repair requires an iPhoneOS device IPA. Simulator and other-platform apps are not supported.");
    }
    if team.len() != 10 || !team.bytes().all(|c| c.is_ascii_uppercase() || c.is_ascii_digit()) {
        bail!("The selected Apple team identifier is invalid.");
    }
    if info.get("NSHealthShareUsageDescription").and_then(Value::as_string).is_none_or(|s| s.trim().is_empty()) {
        bail!("The original Luqma IPA must contain a meaningful Health read permission description.");
    }
    if info.contains_key("NSHealthUpdateUsageDescription") {
        bail!("This Luqma repair is limited to the approved read-only Health integration.");
    }
    if has_nested_apps {
        bail!("This Luqma repair does not support app extensions, App Clips or Watch companions; no additional App IDs were registered.");
    }
    let device = device_udid.filter(|value| !value.trim().is_empty())
        .ok_or_else(|| report!("Select the already registered iPhone before repairing Luqma."))?;
    let bundle_id = format!("{ORIGINAL_BUNDLE_ID}.{team}");
    Ok(RepairTarget {
        group_identifier: format!("group.{bundle_id}"),
        bundle_id,
        device_udid: device.to_string(),
    })
}

pub(crate) fn existing_app_id(ids: &[AppId], target: &RepairTarget) -> Result<AppId, Report> {
    let mut found = ids.iter().filter(|id| id.identifier == target.bundle_id);
    let id = found.next().ok_or_else(|| report!("Luqma's exact final App ID is not already registered on the selected Apple team. This repair will not create or delete App IDs."))?;
    if found.next().is_some() || id.app_id_id.is_empty() {
        bail!("Apple returned ambiguous or invalid metadata for Luqma's existing App ID.");
    }
    Ok(id.clone())
}

pub(crate) fn registered_device(devices: &[DeveloperDevice], target: &RepairTarget) -> Result<(), Report> {
    if !devices.iter().any(|device| device.device_number == target.device_udid) {
        bail!("The selected iPhone is not already registered on this Apple team. No device was added by this repair.");
    }
    Ok(())
}

pub(crate) fn existing_app_group(groups: &[AppGroup], target: &RepairTarget) -> Result<AppGroup, Report> {
    let mut found = groups.iter().filter(|group| group.identifier == target.group_identifier);
    let group = found.next().ok_or_else(|| report!("Luqma's existing App Group is unavailable. This repair will not register another group or App ID."))?;
    if found.next().is_some() || group.application_group.is_empty() {
        bail!("Apple returned ambiguous or invalid metadata for Luqma's existing App Group.");
    }
    Ok(group.clone())
}

fn array_contains(value: Option<&Value>, expected: &str) -> bool {
    value.and_then(Value::as_array).is_some_and(|values| {
        !values.is_empty() && values.iter().all(|value| value.as_string().is_some()) &&
            values.iter().any(|value| value.as_string() == Some(expected))
    })
}

/// Pure metadata checks used after Apple's profile download, never to modify its
/// allowlist. Test fixtures for this function are not real signed Apple profiles.
pub(crate) fn validate_profile_metadata(
    profile: &Dictionary,
    team: &str,
    target: &RepairTarget,
    certificate_der: &[u8],
    now: SystemTime,
) -> Result<(), Report> {
    let claims = profile.get("Entitlements").and_then(Value::as_dictionary)
        .ok_or_else(|| report!("Apple's downloaded profile has no entitlement dictionary."))?;
    if claims.get(HEALTHKIT).and_then(Value::as_boolean) != Some(true) {
        bail!("Apple's downloaded profile does not authorize HealthKit. Signing and installation were stopped; no HealthKit entitlement was fabricated.");
    }
    if !array_contains(profile.get("TeamIdentifier"), team) ||
        claims.get("com.apple.developer.team-identifier").and_then(Value::as_string) != Some(team) {
        bail!("Apple's downloaded profile does not match the selected signing team.");
    }
    if !array_contains(profile.get("Platform"), "iOS") {
        bail!("Apple's downloaded profile is not an iOS development profile.");
    }
    let application_id = claims.get("application-identifier").and_then(Value::as_string)
        .ok_or_else(|| report!("Apple's downloaded profile has no explicit application identifier."))?;
    let (prefix, bundle) = application_id.split_once('.')
        .ok_or_else(|| report!("Apple's downloaded profile has an invalid application identifier."))?;
    if bundle != target.bundle_id || prefix.is_empty() ||
        !array_contains(profile.get("ApplicationIdentifierPrefix"), prefix) {
        bail!("Apple's downloaded profile does not match Luqma's exact final bundle identifier.");
    }
    if claims.get("get-task-allow").and_then(Value::as_boolean) != Some(true) {
        bail!("Apple's downloaded profile is not an authorized development profile.");
    }
    if let Some(value) = profile.get("ProvisionsAllDevices") {
        if value.as_boolean() != Some(false) {
            bail!("Enterprise or malformed all-device provisioning is outside this repair.");
        }
    }
    if !array_contains(profile.get("ProvisionedDevices"), &target.device_udid) {
        bail!("Apple's downloaded profile does not include the selected iPhone.");
    }
    let expiration: SystemTime = profile.get("ExpirationDate").and_then(Value::as_date)
        .ok_or_else(|| report!("Apple's downloaded profile has no valid expiration date."))?.into();
    if expiration <= now {
        bail!("Apple's downloaded profile has expired. Installation was stopped.");
    }
    if certificate_der.is_empty() || !profile.get("DeveloperCertificates").and_then(Value::as_array)
        .is_some_and(|certificates| !certificates.is_empty() &&
            certificates.iter().all(|value| value.as_data().is_some()) &&
            certificates.iter().any(|value| value.as_data() == Some(certificate_der))) {
        bail!("Apple's downloaded profile does not authorize the actual signing certificate.");
    }
    Ok(())
}

pub(crate) fn validate_downloaded_profile(
    encoded: &[u8],
    team: &str,
    target: &RepairTarget,
    identity: &CertificateIdentity,
) -> Result<(), Report> {
    let now = SystemTime::now();
    let validity = identity.certificate.tbs_certificate.validity;
    let not_before = UNIX_EPOCH.checked_add(validity.not_before.to_unix_duration())
        .ok_or_else(|| report!("The signing certificate's validity period is invalid."))?;
    let not_after = UNIX_EPOCH.checked_add(validity.not_after.to_unix_duration())
        .ok_or_else(|| report!("The signing certificate's validity period is invalid."))?;
    if now < not_before || now >= not_after {
        bail!("The actual signing certificate is not currently valid.");
    }
    let certificate_der = identity.certificate.to_der()
        .map_err(|_| report!("Could not inspect the actual signing certificate."))?;
    let profile = ProvisioningProfile::parse(encoded)
        .map_err(|_| report!("Apple's downloaded provisioning profile could not be parsed. Signing was stopped."))?;
    validate_profile_metadata(profile.plist(), team, target, &certificate_der, now)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    const TEAM: &str = "A1B2C3D4E5";
    const DEVICE: &str = "synthetic-device-only";
    const CERT: &[u8] = b"synthetic-certificate-not-real-Apple-DER";

    fn info() -> Dictionary {
        let mut info = Dictionary::new();
        info.insert("CFBundleIdentifier".into(), Value::String(ORIGINAL_BUNDLE_ID.into()));
        info.insert("CFBundleSupportedPlatforms".into(), Value::Array(vec![Value::String("iPhoneOS".into())]));
        info.insert("NSHealthShareUsageDescription".into(), Value::String("Read steps, activity, weight and height for your health overview.".into()));
        info
    }
    fn target() -> RepairTarget { repair_target(&info(), TEAM, false, Some(DEVICE)).unwrap() }
    fn app_id() -> AppId {
        AppId { app_id_id: "synthetic-app-id".into(), identifier: target().bundle_id,
            name: "Synthetic Luqma".into(), features: Dictionary::new(), expiration_date: None }
    }
    fn metadata(now: SystemTime) -> Dictionary {
        let target = target();
        let mut claims = Dictionary::new();
        claims.insert(HEALTHKIT.into(), Value::Boolean(true));
        claims.insert("get-task-allow".into(), Value::Boolean(true));
        claims.insert("com.apple.developer.team-identifier".into(), Value::String(TEAM.into()));
        claims.insert("application-identifier".into(), Value::String(format!("{TEAM}.{}", target.bundle_id)));
        let mut profile = Dictionary::new();
        profile.insert("Entitlements".into(), Value::Dictionary(claims));
        for (key, value) in [("TeamIdentifier", TEAM), ("ApplicationIdentifierPrefix", TEAM),
                             ("Platform", "iOS"), ("ProvisionedDevices", DEVICE)] {
            profile.insert(key.into(), Value::Array(vec![Value::String(value.into())]));
        }
        profile.insert("ExpirationDate".into(), Value::Date((now + Duration::from_secs(600)).into()));
        profile.insert("DeveloperCertificates".into(), Value::Array(vec![Value::Data(CERT.to_vec())]));
        profile
    }
    fn check(profile: &Dictionary, now: SystemTime) -> Result<(), Report> {
        validate_profile_metadata(profile, TEAM, &target(), CERT, now)
    }
    fn now() -> SystemTime { UNIX_EPOCH + Duration::from_secs(1_800_000_000) }

    #[test]
    fn preflight_targets_only_the_original_luqma_and_exact_team_suffix() {
        assert_eq!(target().bundle_id, format!("{ORIGINAL_BUNDLE_ID}.{TEAM}"));
        for bundle in ["com.example.other", "app.luqma.diary.A1B2C3D4E5", "app.luqma.diary.A1B2C3D4E5.A1B2C3D4E5"] {
            let mut value = info(); value.insert("CFBundleIdentifier".into(), Value::String(bundle.into()));
            assert!(repair_target(&value, TEAM, false, Some(DEVICE)).is_err());
        }
    }
    #[test]
    fn preflight_rejects_missing_or_wrong_type_read_purpose() {
        for value in [None, Some(Value::String("  ".into())), Some(Value::Boolean(true))] {
            let mut data = info(); data.remove("NSHealthShareUsageDescription");
            if let Some(value) = value { data.insert("NSHealthShareUsageDescription".into(), value); }
            assert!(repair_target(&data, TEAM, false, Some(DEVICE)).is_err());
        }
    }
    #[test]
    fn preflight_rejects_simulator_missing_or_ambiguous_platform_receipts() {
        for platform in [None, Some(Value::String("iPhoneOS".into())),
            Some(Value::Array(vec![Value::String("iPhoneSimulator".into())])),
            Some(Value::Array(vec![Value::String("iPhoneOS".into()), Value::String("iPhoneSimulator".into())]))] {
            let mut data = info(); data.remove("CFBundleSupportedPlatforms");
            if let Some(platform) = platform { data.insert("CFBundleSupportedPlatforms".into(), platform); }
            assert!(repair_target(&data, TEAM, false, Some(DEVICE)).is_err());
        }
    }
    #[test]
    fn unrelated_memory_capability_fails_in_pure_preflight() {
        assert!(validate_repair_options(false).is_ok());
        assert!(validate_repair_options(true).is_err());
    }
    #[test]
    fn preflight_rejects_extensions_write_intent_invalid_team_or_missing_device() {
        assert!(repair_target(&info(), TEAM, true, Some(DEVICE)).is_err());
        assert!(repair_target(&info(), "bad-team", false, Some(DEVICE)).is_err());
        assert!(repair_target(&info(), TEAM, false, None).is_err());
        let mut value = info(); value.insert("NSHealthUpdateUsageDescription".into(), Value::String("Write".into()));
        assert!(repair_target(&value, TEAM, false, Some(DEVICE)).is_err());
    }
    #[test]
    fn missing_or_ambiguous_app_ids_fail_in_pure_preflight() {
        assert!(existing_app_id(&[], &target()).is_err());
        assert!(existing_app_id(&[app_id()], &target()).is_ok());
        assert!(existing_app_id(&[app_id(), app_id()], &target()).is_err());
        let mut id = app_id(); id.identifier = "app.luqma.diary.WRONGTEAM1".into();
        assert!(existing_app_id(&[id], &target()).is_err());
    }
    #[test]
    fn preflight_requires_an_existing_group_and_registered_phone() {
        assert!(existing_app_group(&[], &target()).is_err());
        let group = AppGroup { name: None, identifier: target().group_identifier,
            application_group: "synthetic-existing-group".into() };
        assert!(existing_app_group(&[group], &target()).is_ok());
        assert!(registered_device(&[], &target()).is_err());
        let device = DeveloperDevice { name: None, device_id: None, device_number: DEVICE.into(), status: None };
        assert!(registered_device(&[device], &target()).is_ok());
    }
    #[test]
    fn valid_metadata_matches_current_identity_target_phone_and_health_capability() {
        assert!(check(&metadata(now()), now()).is_ok());
    }
    #[test]
    fn health_is_required_as_boolean_true_not_a_coerced_value() {
        for value in [None, Some(Value::Boolean(false)), Some(Value::Integer(1.into())), Some(Value::String("true".into()))] {
            let mut profile = metadata(now()); let claims = profile.get_mut("Entitlements").unwrap().as_dictionary_mut().unwrap();
            claims.remove(HEALTHKIT); if let Some(value) = value { claims.insert(HEALTHKIT.into(), value); }
            assert!(check(&profile, now()).is_err());
        }
    }
    #[test]
    fn wrong_team_or_final_identifier_fails_without_rewriting_the_profile() {
        let original = metadata(now());
        let mut profile = original.clone(); profile.insert("TeamIdentifier".into(), Value::Array(vec![Value::String("WRONGTEAM1".into())]));
        assert!(check(&profile, now()).is_err());
        for key in ["application-identifier", "com.apple.developer.team-identifier"] {
            let mut profile = original.clone(); profile.get_mut("Entitlements").unwrap().as_dictionary_mut().unwrap().insert(key.into(), Value::String("WRONGTEAM1.some.other.bundle".into()));
            assert!(check(&profile, now()).is_err());
        }
        assert!(check(&original, now()).is_ok());
    }
    #[test]
    fn legacy_app_prefix_can_differ_from_team_when_profile_authorizes_it() {
        let mut profile = metadata(now());
        profile.insert("ApplicationIdentifierPrefix".into(), Value::Array(vec![Value::String("OLDPREFIX1".into())]));
        profile.get_mut("Entitlements").unwrap().as_dictionary_mut().unwrap().insert("application-identifier".into(), Value::String(format!("OLDPREFIX1.{}", target().bundle_id)));
        assert!(check(&profile, now()).is_ok());
    }
    #[test]
    fn expired_profile_missing_device_or_wrong_certificate_fails() {
        for key in ["ExpirationDate", "ProvisionedDevices", "DeveloperCertificates"] {
            let mut profile = metadata(now()); profile.remove(key);
            assert!(check(&profile, now()).is_err());
        }
        let mut profile = metadata(now()); profile.insert("ExpirationDate".into(), Value::Date(now().into()));
        assert!(check(&profile, now()).is_err());
        profile = metadata(now()); profile.insert("ProvisionedDevices".into(), Value::Array(vec![Value::String("another-synthetic-device".into())]));
        assert!(check(&profile, now()).is_err());
        assert!(validate_profile_metadata(&metadata(now()), TEAM, &target(), b"different-certificate", now()).is_err());
    }
    #[test]
    fn wrong_platform_wildcard_and_enterprise_profiles_fail() {
        let mut profile = metadata(now()); profile.insert("Platform".into(), Value::Array(vec![Value::String("OSX".into())]));
        assert!(check(&profile, now()).is_err());
        profile = metadata(now()); profile.insert("ProvisionsAllDevices".into(), Value::Boolean(true));
        assert!(check(&profile, now()).is_err());
        profile = metadata(now()); profile.get_mut("Entitlements").unwrap().as_dictionary_mut().unwrap().insert("application-identifier".into(), Value::String(format!("{TEAM}.*")));
        assert!(check(&profile, now()).is_err());
    }
    #[test]
    fn distribution_or_wrong_type_debug_permissions_fail() {
        for value in [Value::Boolean(false), Value::Integer(1.into()), Value::String("true".into())] {
            let mut profile = metadata(now()); profile.get_mut("Entitlements").unwrap().as_dictionary_mut().unwrap().insert("get-task-allow".into(), value);
            assert!(check(&profile, now()).is_err());
        }
    }
}
