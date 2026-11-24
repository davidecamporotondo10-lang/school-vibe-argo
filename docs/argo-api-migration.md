# Argo API compatibility correction

The reported failure is HTML with HTTP 503 at application login, after OAuth.
The official app works on the same networks. Public integrations now use
`https://didattica.portaleargo.it/famiglia/api/` rather than the previous
`https://www.portaleargo.it/appfamiglia/api/rest/`.

References inspected (community integrations, not official Argo documentation):
- https://github.com/power80it/ha-didup/blob/72964b755f733333dd098469141fea05371fc98a/custom_components/didup/api.py
  Documents the old API returning 503; uses the new base, `os-type: WEB`,
  and client version `4.3.0`.
- https://github.com/lpaladini1980/minerva-android/blob/324c76bfdbf5f195562172c53467a14a5707e551/app/src/it/paladia/minerva/core/Argo.java
  Independently uses the new base and `os-type: WEB` for application requests.

Scope: switch login (including retry), profile and dashboard to one shared base;
add the application API header and update the minimum advertised client version.
OAuth URLs, PKCE, credentials, refresh logic, request bodies, account selection,
data mapping, local storage and timetable import are unchanged.

Source regression checks verify that only these intentional API changes and the
previous response validation differ from the original transport implementation;
the OAuth code is checked byte-for-byte. They do not prove server compatibility.
An authenticated end-to-end test still needs the APK on the user's device.
No credentials or raw server responses are recorded.
