// Turbo re-runs this script when its data attributes change (sign in, sign
// out), so keep everything block-scoped.
{
  const { posthogToken, posthogHost, posthogUiHost, posthogUserId, posthogProperties, posthogReset } = document.currentScript.dataset;
  !function(t,e){var o,n,p,r;e.__SV||(window.posthog=e,e._i=[],e.init=function(i,s,a){function g(t,e){var o=e.split(".");2==o.length&&(t=t[o[0]],e=o[1]),t[e]=function(){t.push([e].concat(Array.prototype.slice.call(arguments,0)))}}(p=t.createElement("script")).type="text/javascript",p.crossOrigin="anonymous",p.async=!0,p.src=s.api_host.replace(".i.posthog.com","-assets.i.posthog.com")+"/static/array.js",(r=t.getElementsByTagName("script")[0]).parentNode.insertBefore(p,r);var u=e;for(void 0!==a?u=e[a]=[]:a="posthog",u.people=u.people||[],Object.defineProperty(u,"toString",{configurable:!0,enumerable:!0,writable:!0,value:function(t){var e="posthog";return"posthog"!==a&&(e+="."+a),t||(e+=" (stub)"),e}}),Object.defineProperty(u.people,"toString",{configurable:!0,enumerable:!0,writable:!0,value:function(){return u.toString(1)+".people (stub)"}}),o="init capture register register_once register_for_session unregister unregister_for_session getFeatureFlag getFeatureFlagResult isFeatureEnabled reloadFeatureFlags updateEarlyAccessFeatureEnrollment getEarlyAccessFeatures on onFeatureFlags onSessionId getSurveys getActiveMatchingSurveys renderSurvey canRenderSurvey getNextSurveyStep identify setPersonProperties group resetGroups setPersonPropertiesForFlags resetPersonPropertiesForFlags setGroupPropertiesForFlags resetGroupPropertiesForFlags reset get_distinct_id getGroups get_session_id get_session_replay_url alias set_config startSessionRecording stopSessionRecording sessionRecordingStarted captureException loadToolbar get_property getSessionProperty createPersonProfile opt_in_capturing opt_out_capturing has_opted_in_capturing has_opted_out_capturing clear_opt_in_out_capturing debug".split(" "),n=0;n<o.length;n++)g(u,o[n]);e._i.push([i,s,a])},e.__SV=1)}(document,window.posthog||[]);
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
    defaults: "2026-05-30",
    autocapture: true,
    capture_dead_clicks: true,
    person_profiles: "identified_only"
  })
  // reset() also clears registered properties, so it runs before register.
  if (posthogReset) posthog.reset()
  posthog.register(JSON.parse(posthogProperties))
  if (posthogUserId) posthog.identify(posthogUserId)
}
