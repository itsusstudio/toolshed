// Turbo re-runs this script when its data attributes change (sign in, sign
// out), so keep everything block-scoped.
{
  const { posthogToken, posthogHost, posthogUiHost, posthogDefaults, posthogMaskedPaths, posthogUserId, posthogTenantId, posthogProperties } = document.currentScript.dataset;
  // Some URLs work as keys (share links, password resets), so URLs lose
  // their query, and masked paths are cut to their prefix. Walks the whole
  // event, as PostHog's before_send redaction guide does, so nested URLs in
  // replay and web vitals are covered too.
  const maskedPaths = JSON.parse(posthogMaskedPaths)
  const redactUrl = (value) => {
    if (!/^(https?:|\/)/i.test(value)) return value
    let url
    try { url = new URL(value, location.origin) } catch { return value }
    const path = maskedPaths.find((prefix) => url.pathname.startsWith(prefix)) || url.pathname
    return value.startsWith("/") ? path : url.origin + path
  }
  const redact = (value, key = "") => {
    if (typeof value === "string") return /(url|pathname|referrer|href)$/i.test(key) ? redactUrl(value) : value
    if (Array.isArray(value)) return value.map((item) => redact(item, key))
    if (value && typeof value === "object") {
      for (const name in value) value[name] = redact(value[name], name)
    }
    return value
  }
  // PostHog's loader stub, from Project settings > Web snippet (2026-11-07).
  // It only queues calls until array.js, always the latest SDK, loads, so
  // refresh it when PostHog's snippet changes rather than for SDK updates.
  !function(t,e){var o,n,p,r;e.__SV||(window.posthog && window.posthog.__loaded)||(window.posthog=e,e._i=[],e.init=function(i,s,a){function g(t,e){var o=e.split(".");2==o.length&&(t=t[o[0]],e=o[1]),t[e]=function(){t.push([e].concat(Array.prototype.slice.call(arguments,0)))}}p||((p=t.createElement("script")).type="text/javascript",p.crossOrigin="anonymous",p.async=!0,p.src=s.api_host.replace(".i.posthog.com","-assets.i.posthog.com")+"/static/array.js",p.onerror=function(){p=null},(r=t.getElementsByTagName("script")[0]).parentNode.insertBefore(p,r));var u=e;for(void 0!==a?u=e[a]=[]:a="posthog",u.people=u.people||[],Object.defineProperty(u,"toString",{configurable:!0,enumerable:!0,writable:!0,value:function(t){var e="posthog";return"posthog"!==a&&(e+="."+a),t||(e+=" (stub)"),e}}),Object.defineProperty(u.people,"toString",{configurable:!0,enumerable:!0,writable:!0,value:function(){return u.toString(1)+".people (stub)"}}),o="mh bh wh xh init Xh ed Gh Jh od ac Yh ad Uh fd pd gd md yd bd capture getExtension nd mr Zh Kh calculateEventProperties wd register register_once register_for_session unregister unregister_for_session Cd Vh Sd getFeatureFlag getFeatureFlagPayload getFeatureFlagResult getAllFeatureFlags isFeatureEnabled reloadFeatureFlags updateFlags updateEarlyAccessFeatureEnrollment getEarlyAccessFeatures on onFeatureFlags onSurveysLoaded onSessionId getSurveys getActiveMatchingSurveys onActiveMatchingSurveysChanged renderSurvey displaySurvey cancelPendingSurvey canRenderSurvey canRenderSurveyAsync Td identify setPersonProperties unsetPersonProperties group resetGroups setPersonPropertiesForFlags resetPersonPropertiesForFlags setGroupPropertiesForFlags resetGroupPropertiesForFlags reset Id shutdown setIdentity clearIdentity get_distinct_id getGroups get_session_id get_session_replay_url alias set_config startSessionRecording stopSessionRecording sessionRecordingStarted captureException addExceptionStep captureLog startExceptionAutocapture stopExceptionAutocapture loadToolbar get_property getSessionProperty xd hd createPersonProfile setInternalOrTestUser $d Ih Ch opt_in_capturing opt_out_capturing Th has_opted_in_capturing has_opted_out_capturing get_explicit_consent_status is_capturing clear_opt_in_out_capturing ld debug lc Fs getPageViewId captureTraceFeedback captureTraceMetric qh".split(" "),n=0;n<o.length;n++)g(u,o[n]);e._i.push([i,s,a])},e.__SV=1)}(document,window.posthog||[]);
  // A signed-out page drops an identified browser's identity, so the next
  // person on the device starts fresh. That needs the loaded SDK: the stub
  // can't say whether the browser is identified. reset() also clears
  // registered properties and groups, so it runs first.
  const syncIdentity = (ph) => {
    if (!posthogUserId && ph.get_property("$user_state") === "identified") ph.reset()
    ph.register(JSON.parse(posthogProperties))
    if (posthogUserId) ph.identify(posthogUserId)
    if (posthogTenantId) ph.group("tenant", posthogTenantId)
  }
  // Once loaded, a Turbo re-run only refreshes identity and properties.
  if (window.posthog.__loaded) {
    syncIdentity(window.posthog)
  } else if (!window.posthog._i?.length) {
    posthog.init(posthogToken, {
      api_host: posthogHost,
      ui_host: posthogUiHost,
      tracing_headers: [location.hostname],
      session_recording: {
        // Page text is masked like inputs: shown only inside [data-replay-unmask].
        maskTextSelector: "*",
        maskTextFn: (text, element) => element?.closest("[data-replay-unmask]") ? text : text.replace(/\S/g, "*"),
        blockSelector: 'a[href^="mailto:"], a[href^="tel:"]',
        maskCapturedNetworkRequestFn: (request) => ({...request, name: redactUrl(request.name)}),
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
      disable_capture_url_hashes: true,
      before_send: (event) => {
        if (event) ["properties", "$set", "$set_once"].forEach((part) => redact(event[part]))
        return event
      },
      // Autocapture keeps what was clicked, never its text or attributes, so
      // a customer's name or mailto: link never leaves the page.
      mask_all_text: true,
      mask_all_element_attributes: true,
      autocapture: true,
      capture_dead_clicks: true,
      person_profiles: "identified_only",
      loaded: syncIdentity
    })
  }
}
