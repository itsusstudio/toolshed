// Turbo re-runs this script when its data attributes change (sign in, sign
// out), so keep everything block-scoped.
{
  const { posthogToken, posthogHost, posthogUiHost, posthogDefaults, posthogUserId, posthogTenantId, posthogProperties, posthogReset } = document.currentScript.dataset;
  // PostHog's loader stub, from Project settings > Web snippet (2026-11-07).
  // It only queues calls until array.js, always the latest SDK, loads, so
  // refresh it when PostHog's snippet changes rather than for SDK updates.
  !function(t,e){var o,n,p,r;e.__SV||(window.posthog && window.posthog.__loaded)||(window.posthog=e,e._i=[],e.init=function(i,s,a){function g(t,e){var o=e.split(".");2==o.length&&(t=t[o[0]],e=o[1]),t[e]=function(){t.push([e].concat(Array.prototype.slice.call(arguments,0)))}}p||((p=t.createElement("script")).type="text/javascript",p.crossOrigin="anonymous",p.async=!0,p.src=s.api_host.replace(".i.posthog.com","-assets.i.posthog.com")+"/static/array.js",p.onerror=function(){p=null},(r=t.getElementsByTagName("script")[0]).parentNode.insertBefore(p,r));var u=e;for(void 0!==a?u=e[a]=[]:a="posthog",u.people=u.people||[],Object.defineProperty(u,"toString",{configurable:!0,enumerable:!0,writable:!0,value:function(t){var e="posthog";return"posthog"!==a&&(e+="."+a),t||(e+=" (stub)"),e}}),Object.defineProperty(u.people,"toString",{configurable:!0,enumerable:!0,writable:!0,value:function(){return u.toString(1)+".people (stub)"}}),o="mh bh wh xh init Xh ed Gh Jh od ac Yh ad Uh fd pd gd md yd bd capture getExtension nd mr Zh Kh calculateEventProperties wd register register_once register_for_session unregister unregister_for_session Cd Vh Sd getFeatureFlag getFeatureFlagPayload getFeatureFlagResult getAllFeatureFlags isFeatureEnabled reloadFeatureFlags updateFlags updateEarlyAccessFeatureEnrollment getEarlyAccessFeatures on onFeatureFlags onSurveysLoaded onSessionId getSurveys getActiveMatchingSurveys onActiveMatchingSurveysChanged renderSurvey displaySurvey cancelPendingSurvey canRenderSurvey canRenderSurveyAsync Td identify setPersonProperties unsetPersonProperties group resetGroups setPersonPropertiesForFlags resetPersonPropertiesForFlags setGroupPropertiesForFlags resetGroupPropertiesForFlags reset Id shutdown setIdentity clearIdentity get_distinct_id getGroups get_session_id get_session_replay_url alias set_config startSessionRecording stopSessionRecording sessionRecordingStarted captureException addExceptionStep captureLog startExceptionAutocapture stopExceptionAutocapture loadToolbar get_property getSessionProperty xd hd createPersonProfile setInternalOrTestUser $d Ih Ch opt_in_capturing opt_out_capturing Th has_opted_in_capturing has_opted_out_capturing get_explicit_consent_status is_capturing clear_opt_in_out_capturing ld debug lc Fs getPageViewId captureTraceFeedback captureTraceMetric qh".split(" "),n=0;n<o.length;n++)g(u,o[n]);e._i.push([i,s,a])},e.__SV=1)}(document,window.posthog||[]);
  // Once loaded, a Turbo re-run only refreshes identity and properties.
  if (!window.posthog.__loaded && !window.posthog._i?.length) {
    posthog.init(posthogToken, {
      api_host: posthogHost,
      ui_host: posthogUiHost,
      tracing_headers: [location.hostname],
      session_recording: {
        maskAllInputs: true,
        // Every input is masked unless a field opts in. Secrets, contact details
        // and data-replay-mask stay masked even inside an opted-in form.
        maskInputFn: (text, element) => {
          // autocomplete can carry several tokens, like "section-pay cc-number".
          const tokens = (element?.getAttribute?.("autocomplete") || "").toLowerCase().split(/\s+/)
          const secretToken = (token) => ["current-password", "new-password", "one-time-code", "email"].includes(token) ||
            token.startsWith("cc-") || token.startsWith("tel")
          const secret = ["password", "email", "tel"].includes(element?.type) ||
            tokens.some(secretToken) || element?.closest("[data-replay-mask]")
          return element?.closest("[data-replay-unmask]") && !secret ? text : "*".repeat(text.length)
        }
      },
      defaults: posthogDefaults,
      autocapture: true,
      capture_dead_clicks: true,
      person_profiles: "identified_only"
    })
  }
  // reset() also clears registered properties and groups, so it runs first.
  if (posthogReset) posthog.reset()
  posthog.register(JSON.parse(posthogProperties))
  if (posthogUserId) posthog.identify(posthogUserId)
  if (posthogTenantId) posthog.group("tenant", posthogTenantId)
}
