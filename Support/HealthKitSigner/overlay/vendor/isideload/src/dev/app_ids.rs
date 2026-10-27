use crate::{
    dev::{
        developer_session::DeveloperSession,
        device_type::{DeveloperDeviceType, dev_url},
        normalize_app_names,
        teams::DeveloperTeam,
    },
    util::plist::{PlistDataExtract, SensitivePlistAttachment},
};
use plist::{Data, Date, Dictionary, Value};
use plist_macro::plist;
use reqwest::header::HeaderValue;
use rootcause::prelude::*;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AppId {
    pub app_id_id: String,
    pub identifier: String,
    pub name: String,
    pub features: Dictionary,
    pub expiration_date: Option<Date>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ListAppIdsResponse {
    pub app_ids: Vec<AppId>,
    pub max_quantity: Option<u64>,
    pub available_quantity: Option<i64>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Profile {
    pub encoded_profile: Data,
    pub filename: String,
    pub provisioning_profile_id: String,
    pub name: String,
    pub status: String,
    pub r#type: String,
    pub distribution_method: String,
    pub pro_pro_platorm: Option<String>,
    #[serde(rename = "UUID")]
    pub uuid: String,
    pub date_expire: Date,
    pub managing_app: Option<String>,
    pub app_id_id: String,
    pub is_template_profile: bool,
    pub is_team_profile: Option<bool>,
    pub is_free_provisioning_profile: Option<bool>,
}

#[cfg_attr(feature = "wasm", async_trait::async_trait(?Send))]
#[cfg_attr(not(feature = "wasm"), async_trait::async_trait)]
pub trait AppIdsApi {
    fn developer_session(&mut self) -> &mut DeveloperSession;

    async fn add_app_id(
        &mut self,
        team: &DeveloperTeam,
        name: &str,
        identifier: &str,
        device_type: impl Into<Option<DeveloperDeviceType>> + Send,
    ) -> Result<AppId, Report> {
        let body = plist!(dict {
            "teamId": &team.team_id,
            "identifier": identifier,
            "name": normalize_app_names(name),
        });

        let app_id: AppId = self
            .developer_session()
            .send_dev_request(&dev_url("addAppId", device_type), body, "appId")
            .await
            .context("Failed to add developer app ID")?;

        Ok(app_id)
    }

    async fn list_app_ids(
        &mut self,
        team: &DeveloperTeam,
        device_type: impl Into<Option<DeveloperDeviceType>> + Send,
    ) -> Result<ListAppIdsResponse, Report> {
        let body = plist!(dict {
            "teamId": &team.team_id,
        });

        let response: Value = self
            .developer_session()
            .send_dev_request_no_response(&dev_url("listAppIds", device_type), body)
            .await
            .context("Failed to list developer app IDs")?
            .into();

        let app_ids: ListAppIdsResponse = plist::from_value(&response).map_err(|e| {
            report!("Failed to deserialize app id response: {:?}", e).attach(
                SensitivePlistAttachment::new(
                    response
                        .as_dictionary()
                        .unwrap_or(&Dictionary::new())
                        .clone(),
                ),
            )
        })?;

        Ok(app_ids)
    }

    async fn update_app_id(
        &mut self,
        team: &DeveloperTeam,
        app_id: &AppId,
        features: Dictionary,
        device_type: impl Into<Option<DeveloperDeviceType>> + Send,
    ) -> Result<AppId, Report> {
        let mut body = plist!(dict {
            "teamId": &team.team_id,
            "appIdId": &app_id.app_id_id
        });

        for (key, value) in features {
            body.insert(key.clone(), value.clone());
        }

        Ok(self
            .developer_session()
            .send_dev_request(&dev_url("updateAppId", device_type), body, "appId")
            .await
            .context("Failed to update developer app ID")?)
    }

    async fn delete_app_id(
        &mut self,
        team: &DeveloperTeam,
        app_id_id: &str,
        device_type: impl Into<Option<DeveloperDeviceType>> + Send,
    ) -> Result<(), Report> {
        let body = plist!(dict {
            "teamId": &team.team_id,
            "appIdId": app_id_id,
        });

        self.developer_session()
            .send_dev_request_no_response(&dev_url("deleteAppId", device_type), body)
            .await
            .context("Failed to delete developer app ID")?;

        Ok(())
    }

    async fn download_team_provisioning_profile(
        &mut self,
        team: &DeveloperTeam,
        app_id: &AppId,
        device_type: impl Into<Option<DeveloperDeviceType>> + Send,
    ) -> Result<Profile, Report> {
        let body = plist!(dict {
            "teamId": &team.team_id,
            "appIdId": &app_id.app_id_id,
        });

        let response: Profile = self
            .developer_session()
            .send_dev_request(
                &dev_url("downloadTeamProvisioningProfile", device_type),
                body,
                "provisioningProfile",
            )
            .await
            .context("Failed to download provisioning profile")?;

        Ok(response)
    }

    async fn add_increased_memory_limit(
        &mut self,
        team: &DeveloperTeam,
        app_id: &AppId,
    ) -> Result<(), Report> {
        let dev_session = self.developer_session();

        let mut headers = dev_session
            .get_headers()
            .await
            .context("Failed to get anisette headers")?;
        headers.insert(
            "Content-Type",
            HeaderValue::from_static("application/vnd.api+json"),
        );
        headers.insert(
            "Accept",
            HeaderValue::from_static("application/vnd.api+json"),
        );

        dev_session
                .get_grandslam_client()
                .patch(&format!(
                    "https://developerservices2.apple.com/services/v1/bundleIds/{}",
                    app_id.app_id_id
                ))?
                .headers(headers)
                .body(format!(
                "{{\"data\":{{\"relationships\":{{\"bundleIdCapabilities\":{{\"data\":[{{\"relationships\":{{\"capability\":{{\"data\":{{\"id\":\"INCREASED_MEMORY_LIMIT\",\"type\":\"capabilities\"}}}}}},\"type\":\"bundleIdCapabilities\",\"attributes\":{{\"settings\":[],\"enabled\":true}}}}]}}}},\"id\":\"{}\",\"attributes\":{{\"hasExclusiveManagedCapabilities\":false,\"teamId\":\"{}\",\"bundleType\":\"bundle\",\"identifier\":\"{}\",\"seedId\":\"{}\",\"name\":\"{}\"}},\"type\":\"bundleIds\"}}}}",
                app_id.app_id_id, team.team_id, app_id.identifier, team.team_id, app_id.name
            ))
                .send()
                .await.context("Failed to request increased memory entitlement")?
                .error_for_status().context("Failed to add increased memory entitlement")?;

        Ok(())
    }
}

impl AppIdsApi for DeveloperSession {
    fn developer_session(&mut self) -> &mut DeveloperSession {
        self
    }
}

const HEALTHKIT_SERVICE_ID: &str = "HK421J6T7P";

fn healthkit_feature_enabled(features: &Dictionary) -> bool {
    features
        .get(HEALTHKIT_SERVICE_ID)
        .and_then(Value::as_boolean)
        == Some(true)
}

fn healthkit_update_body(app_id: &AppId, team: &DeveloperTeam) -> Dictionary {
    // Preserve every existing feature. An update must not disable App Groups or
    // another already configured capability while enabling HealthKit.
    let mut body = app_id.features.clone();
    body.insert(HEALTHKIT_SERVICE_ID.into(), Value::Boolean(true));
    // Feature keys cannot override the authenticated request's target.
    body.insert("teamId".into(), Value::String(team.team_id.clone()));
    body.insert("appIdId".into(), Value::String(app_id.app_id_id.clone()));
    body
}

fn validated_healthkit_update(response: &Dictionary, previous: &AppId) -> Result<AppId, Report> {
    // send_dev_request can return a payload alongside an Apple error. Require a
    // typed, explicit success status even when an otherwise valid appId exists.
    if response.get("resultCode").and_then(Value::as_signed_integer) != Some(0) {
        bail!("Apple did not confirm a successful HealthKit capability update.");
    }
    let value = response
        .get("appId")
        .filter(|value| value.as_dictionary().is_some())
        .ok_or_else(|| report!("Apple returned an invalid HealthKit App ID response."))?;
    let updated: AppId = plist::from_value(value)
        .map_err(|_| report!("Apple returned an invalid HealthKit App ID response."))?;
    if updated.app_id_id != previous.app_id_id || updated.identifier != previous.identifier {
        bail!("Apple's HealthKit response changed the requested existing App ID.");
    }
    if !healthkit_feature_enabled(&updated.features) {
        bail!("Apple did not enable the requested HealthKit capability.");
    }
    if previous.features.iter().any(|(key, value)| {
        value.as_boolean() == Some(true)
            && updated.features.get(key).and_then(Value::as_boolean) != Some(true)
    }) {
        bail!("Apple's HealthKit response did not preserve an existing enabled capability.");
    }
    Ok(updated)
}

impl AppId {
    /// Request HealthKit for this existing iOS App ID through Apple's service.
    ///
    /// Adapted from Rzbck/isideload commit 5e28adc40dac7b108bc89c0dccd28dc0d7bc9e1f
    /// (MIT, upstream copyright nab138). This does not fabricate a profile or
    /// grant access: Apple must accept the request, and the caller must verify
    /// HealthKit in the subsequently downloaded profile before signing.
    pub async fn ensure_healthkit_feature(
        &mut self,
        dev_session: &mut DeveloperSession,
        team: &DeveloperTeam,
    ) -> Result<(), Report> {
        if healthkit_feature_enabled(&self.features) {
            return Ok(());
        }
        let body = healthkit_update_body(self, team);
        // Unlike send_dev_request, this rejects a server error even if Apple
        // also returned appId data. Never propagate server payloads/credentials
        // through this method's diagnostic chain.
        let response = dev_session
            .send_dev_request_no_response(&dev_url("updateAppId", None), body)
            .await
            .map_err(|_| {
                report!("Apple HealthKit capability update failed; no profile was authorized by this check.")
            })?;
        let updated = validated_healthkit_update(&response, self)?;
        self.features = updated.features;
        Ok(())
    }

    pub async fn ensure_group_feature(
        &mut self,
        dev_session: &mut DeveloperSession,
        team: &DeveloperTeam,
    ) -> Result<(), Report> {
        let app_group_feature_enabled = self.features.get_bool("APG3427HIY")?;

        if !app_group_feature_enabled {
            let body = plist!(dict {
                "APG3427HIY": true,
            });
            let new_features = dev_session
                .update_app_id(team, self, body, None)
                .await?
                .features;
            self.features = new_features;
        }

        Ok(())
    }
}

#[cfg(test)]
mod healthkit_feature_tests {
    use super::*;

    fn registered_app() -> AppId {
        AppId {
            app_id_id: "synthetic-existing-app-id".into(),
            identifier: "app.example.health".into(),
            name: "Synthetic App".into(),
            features: plist!(dict {
                "APG3427HIY": true,
                "another-enabled-feature": true,
                "disabled-feature": false,
                "feature-setting": "unchanged",
            }),
            expiration_date: None,
        }
    }

    fn team() -> DeveloperTeam {
        DeveloperTeam {
            name: None,
            team_id: "A1B2C3D4E5".into(),
            r#type: None,
            status: None,
        }
    }

    fn successful_response(previous: &AppId) -> Dictionary {
        let mut updated = previous.clone();
        updated
            .features
            .insert(HEALTHKIT_SERVICE_ID.into(), Value::Boolean(true));
        let mut response = Dictionary::new();
        response.insert("resultCode".into(), Value::Integer(0.into()));
        response.insert("appId".into(), plist::to_value(&updated).unwrap());
        response
    }

    fn updated_payload(response: &mut Dictionary) -> &mut Dictionary {
        response
            .get_mut("appId")
            .unwrap()
            .as_dictionary_mut()
            .unwrap()
    }

    fn updated_features(response: &mut Dictionary) -> &mut Dictionary {
        updated_payload(response)
            .get_mut("features")
            .unwrap()
            .as_dictionary_mut()
            .unwrap()
    }

    #[test]
    fn only_boolean_true_means_healthkit_is_enabled() {
        let mut features = Dictionary::new();
        assert!(!healthkit_feature_enabled(&features));
        for value in [
            Value::Boolean(false),
            Value::Integer(1.into()),
            Value::String("true".into()),
            Value::Array(vec![Value::Boolean(true)]),
        ] {
            features.insert(HEALTHKIT_SERVICE_ID.into(), value);
            assert!(!healthkit_feature_enabled(&features));
        }
        features.insert(HEALTHKIT_SERVICE_ID.into(), Value::Boolean(true));
        assert!(healthkit_feature_enabled(&features));
    }

    #[test]
    fn request_preserves_features_without_allowing_target_overrides() {
        let mut app = registered_app();
        app.features
            .insert("teamId".into(), Value::String("untrusted-team".into()));
        app.features
            .insert("appIdId".into(), Value::String("untrusted-app".into()));
        let original = app.features.clone();
        let body = healthkit_update_body(&app, &team());
        assert_eq!(
            body.get("teamId").and_then(Value::as_string),
            Some("A1B2C3D4E5")
        );
        assert_eq!(
            body.get("appIdId").and_then(Value::as_string),
            Some(app.app_id_id.as_str())
        );
        assert!(healthkit_feature_enabled(&body));
        for key in [
            "APG3427HIY",
            "another-enabled-feature",
            "disabled-feature",
            "feature-setting",
        ] {
            assert_eq!(body.get(key), original.get(key));
        }
        assert_eq!(app.features, original);
    }

    #[test]
    fn explicit_success_requires_same_app_and_preserved_enabled_features() {
        let app = registered_app();
        let updated = validated_healthkit_update(&successful_response(&app), &app).unwrap();
        assert_eq!(updated.app_id_id, app.app_id_id);
        assert_eq!(updated.identifier, app.identifier);
        assert!(healthkit_feature_enabled(&updated.features));
        assert_eq!(
            updated.features.get("APG3427HIY").and_then(Value::as_boolean),
            Some(true)
        );
    }

    #[test]
    fn apple_error_is_rejected_even_with_a_complete_success_shaped_payload() {
        let app = registered_app();
        for code in [-1_i64, 1, 9000] {
            let mut response = successful_response(&app);
            response.insert("resultCode".into(), Value::Integer(code.into()));
            assert!(validated_healthkit_update(&response, &app).is_err());
        }
    }

    #[test]
    fn missing_or_mistyped_result_code_is_not_success() {
        let app = registered_app();
        let mut response = successful_response(&app);
        response.remove("resultCode");
        assert!(validated_healthkit_update(&response, &app).is_err());
        for value in [
            Value::Boolean(false),
            Value::String("0".into()),
            Value::Real(0.0),
        ] {
            response.insert("resultCode".into(), value);
            assert!(validated_healthkit_update(&response, &app).is_err());
        }
    }

    #[test]
    fn missing_or_malformed_app_id_payload_is_rejected() {
        let app = registered_app();
        let mut response = successful_response(&app);
        response.remove("appId");
        assert!(validated_healthkit_update(&response, &app).is_err());
        for value in [
            Value::String("invalid".into()),
            Value::Dictionary(Dictionary::new()),
        ] {
            response.insert("appId".into(), value);
            assert!(validated_healthkit_update(&response, &app).is_err());
        }
    }

    #[test]
    fn a_different_existing_record_or_bundle_is_rejected() {
        let app = registered_app();
        for key in ["appIdId", "identifier"] {
            let mut response = successful_response(&app);
            updated_payload(&mut response)
                .insert(key.into(), Value::String("different-target".into()));
            assert!(validated_healthkit_update(&response, &app).is_err());
        }
    }

    #[test]
    fn missing_false_or_mistyped_healthkit_grant_is_rejected() {
        let app = registered_app();
        let mut response = successful_response(&app);
        updated_features(&mut response).remove(HEALTHKIT_SERVICE_ID);
        assert!(validated_healthkit_update(&response, &app).is_err());
        for value in [
            Value::Boolean(false),
            Value::Integer(1.into()),
            Value::String("true".into()),
        ] {
            updated_features(&mut response).insert(HEALTHKIT_SERVICE_ID.into(), value);
            assert!(validated_healthkit_update(&response, &app).is_err());
        }
    }

    #[test]
    fn apple_cannot_silently_drop_an_already_enabled_feature() {
        let app = registered_app();
        for key in ["APG3427HIY", "another-enabled-feature"] {
            let mut response = successful_response(&app);
            updated_features(&mut response).remove(key);
            assert!(validated_healthkit_update(&response, &app).is_err());
            for value in [
                Value::Boolean(false),
                Value::Integer(1.into()),
                Value::String("true".into()),
            ] {
                updated_features(&mut response).insert(key.into(), value);
                assert!(validated_healthkit_update(&response, &app).is_err());
            }
        }
    }

    #[test]
    fn diagnostics_do_not_attach_apple_response_or_identifiers() {
        let app = registered_app();
        let private_marker = "PRIVATE-SYNTHETIC-RESPONSE-MARKER";
        for malformed_payload in [false, true] {
            let mut response = successful_response(&app);
            response.insert("resultString".into(), Value::String(private_marker.into()));
            response.insert("userString".into(), Value::String(private_marker.into()));
            if malformed_payload {
                updated_payload(&mut response)
                    .insert("features".into(), Value::String(private_marker.into()));
            } else {
                response.insert("resultCode".into(), Value::Integer(123.into()));
            }
            let error = validated_healthkit_update(&response, &app).unwrap_err();
            let diagnostic = format!("{error:?} {error}");
            assert!(!diagnostic.contains(private_marker));
            assert!(!diagnostic.contains(&app.app_id_id));
            assert!(!diagnostic.contains(&app.identifier));
        }
    }
}
