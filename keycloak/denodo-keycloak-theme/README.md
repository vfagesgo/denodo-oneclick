# Denodo OneClick Keycloak theme

This theme adapts the supplied Denodo Developer V9 landing page styling for Keycloak login:
- Navy background `#112533`
- Centered white card
- Wide primary sign-in button
- Denodo product identity and copyright footer

## Install

1. Copy this directory to your Keycloak themes directory, for example:
   `/opt/keycloak/themes/denodo-oneclick`
2. Copy your existing `images/denodo_logo.svg` to:
   `login/resources/img/denodo_logo.svg`
3. In the Keycloak Admin Console, open **Realm settings → Themes → Login theme** and select `denodo-oneclick`.
4. If the theme does not appear immediately, restart Keycloak or clear the theme cache according to your deployment setup.

## Compatibility

This is a starting theme based on the classic `keycloak` parent theme. Verify it against your deployed Keycloak version before production use. The form continues to submit through Keycloak's `url.loginAction`; it does not implement authentication itself.

## Notes

- The supplied HTML references a Denodo logo and a ninja graphic. The login theme uses the Denodo logo; the decorative ninja graphic is intentionally omitted from the compact authentication screen.
- Social/identity-provider buttons are not hard-coded. Keycloak can render configured identity providers using its built-in templates; add that section if your realm uses external providers.
