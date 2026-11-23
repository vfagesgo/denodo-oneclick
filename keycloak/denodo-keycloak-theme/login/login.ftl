<#import "template.ftl" as layout>
<@layout.registrationLayout displayMessage=!messagesPerField.existsError('username','password') displayInfo=false; section>
  <#if section = "header">
    ${msg("loginAccountTitle")}
  <#elseif section = "form">
    <div class="denodo-brand">
      <img class="denodo-logo" src="${url.resourcesPath}/img/denodo_logo.svg" alt="Denodo" onerror="this.style.display='none'">
      <div class="denodo-product-name">Developer V9</div>
      <p class="denodo-subtitle">${msg("loginAccountTitle")}</p>
    </div>

    <#if realm.password>
      <form id="kc-form-login" class="${properties.kcFormClass!}" onsubmit="login.disabled = true; return true;" action="${url.loginAction}" method="post">
        <#if !usernameHidden??>
          <div class="${properties.kcFormGroupClass!}">
            <label for="username" class="${properties.kcLabelClass!}">
              <#if !realm.loginWithEmailAllowed>
                ${msg("username")}
              <#elseif !realm.registrationEmailAsUsername>
                ${msg("usernameOrEmail")}
              <#else>
                ${msg("email")}
              </#if>
            </label>
            <input tabindex="1" id="username" name="username" value="${(login.username!'')}" type="text"
              autofocus autocomplete="username"
              aria-invalid="<#if messagesPerField.existsError('username','password')>true</#if>"
              class="${properties.kcInputClass!}" />
            <#if messagesPerField.existsError('username','password')>
              <span class="${properties.kcInputErrorMessageClass!}" aria-live="polite">
                ${kcSanitize(messagesPerField.getFirstError('username','password'))?no_esc}
              </span>
            </#if>
          </div>
        </#if>

        <div class="${properties.kcFormGroupClass!}">
          <label for="password" class="${properties.kcLabelClass!}">${msg("password")}</label>
          <input tabindex="2" id="password" name="password" type="password" autocomplete="current-password"
            aria-invalid="<#if messagesPerField.existsError('username','password')>true</#if>"
            class="${properties.kcInputClass!}" />
        </div>

        <div class="denodo-form-options">
          <#if realm.rememberMe && !usernameHidden??>
            <label class="denodo-remember">
              <#if login.rememberMe??>
                <input tabindex="3" id="rememberMe" name="rememberMe" type="checkbox" checked>
              <#else>
                <input tabindex="3" id="rememberMe" name="rememberMe" type="checkbox">
              </#if>
              ${msg("rememberMe")}
            </label>
          </#if>
          <#if realm.resetPasswordAllowed>
            <a tabindex="5" href="${url.loginResetCredentialsUrl}">${msg("doForgotPassword")}</a>
          </#if>
        </div>

        <div class="${properties.kcFormGroupClass!}">
          <input type="hidden" id="id-hidden-input" name="credentialId" <#if auth.selectedCredential?has_content>value="${auth.selectedCredential}"</#if>/>
          <button tabindex="4" class="denodo-button" name="login" id="kc-login" type="submit">
            ${msg("doLogIn")}
          </button>
        </div>
      </form>
    </#if>
  </#if>
</@layout.registrationLayout>
