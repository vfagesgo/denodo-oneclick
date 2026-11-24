/* Try Denodo trial sign-in details (added for the Try Denodo guided tours).
   Shown in the "Login credentials" dropdowns: the left sidebar of welcome.html, mcp-api.html and
   documentation.html, and the guide of each tour in guided-personas.html.
   The password is set here only. Set it to '' to stop showing it. */
window.TRY_DENODO_LOGINS = {
  password: 'try-Denodo9',
  users: [
    { tour: 'Business Analyst tour', user: 'crestbank_analyst', signin: 'Data Marketplace',
      note: 'For this tour: sign in to Data Marketplace with these credentials.' },
    { tour: 'Data Engineer tour',    user: 'crestbank_engineer', signin: 'Design Studio, Data Marketplace',
      note: 'For this tour: sign in to Design Studio and/or Data Marketplace with this user.' },
    { tour: 'AI Builder tour',       user: 'ai_builder', signin: 'Ask a Question',
      note: 'For this tour: sign in to Ask a Question with these credentials.' }
  ],
  /* signin: the tools each tour's user signs in to (shown in the sidebar); note: shown in that tour's guide */
};
