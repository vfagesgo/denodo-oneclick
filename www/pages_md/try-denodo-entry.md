# Try Denodo: entry from denodo.com

Mockup page: `www/pages/try-denodo-entry-mockup.html` (labelled MOCKUP: it is not the live denodo.com, and its links are for illustration only)

## What the visitor sees

When the page opens, **Try Denodo** in the top navigation is highlighted with a soft pulsing ring, and a note under it reads **Start here: Sign up and get a guided trial of Denodo.** The note can be closed with ×. Both go away once the visitor opens Try Denodo. When the visitor's device asks for reduced motion, the ring does not pulse.

Selecting **Try Denodo** (top navigation) or **Try the Denodo Platform** (hero button) opens a panel on the right of denodo.com. The page behind it is blurred.

### 1. Create your trial account

**Get access to a live Denodo environment in a few minutes**

Your trial includes:
- A live Denodo Platform environment with sample data already connected
- Guided tours for three roles: Business Analyst, Data Engineer and AI Builder
- Real business scenarios: augmenting customer intelligence at a bank, or exploring clinical-trial data and X-ray images with AI (coming soon)

Form fields: Work email, Full name, Company, Country. Button: **Create my trial**.

### 2. Your trial is being prepared

Progress list: Account created · Denodo Platform environment started · Sample data connected · Guided tours ready. Button: **Open your Denodo trial**, which opens `welcome.html`.

What happens next: your trial opens on its welcome page. Choose an industry, then a guided tour for the role you want to play: Business Analyst, Data Engineer or AI Builder.

## Then, on the welcome page (`welcome.html`)

1. **Choose your industry.** Two cards: **Crestbank** (Banking, customer and loan data) and **Medixit** (Pharmaceuticals, clinical-trial and X-ray data). Medixit is greyed out and marked **Coming soon**.
2. **Choose a tour.** After Crestbank is chosen, the three role tours appear: Business Analyst, Data Engineer and AI Builder. Each opens `guided-personas.html?role=analyst|engineer|ai&start=1`. The choice is kept in the browser, so a returning visitor sees the tours straight away.
3. **Tours by use case** sit at the bottom in one compact row, greyed out and marked **Coming soon**.

The left sidebar has a **Login credentials** dropdown: the user for each tour, with the tool it signs in to, and the shared password. The same sidebar, with **Return to trial homepage**, is on `mcp-api.html` and `documentation.html`. Inside each tour, the guide has its own **Login credentials** dropdown with that tour's user and the password, and a note:

| Tour | User | Note |
| --- | --- | --- |
| Business Analyst | `crestbank_analyst` | For this tour: sign in to Data Marketplace with these credentials. |
| Data Engineer | `crestbank_engineer` | For this tour: sign in to Design Studio and/or Data Marketplace with this user. |
| AI Builder | `ai_builder` | For this tour: sign in to Ask a Question with these credentials. |

The users and the password are set in one file: `www/assets/js/trial-logins.js`.

## Behaviour

- Close the panel with ×, the Esc key or a click outside it. Focus stays inside the panel while it is open.
- **Back** returns to the sign-up form.
- Full-width panel on mobile.
- Sign-up and environment preparation are simulated in the mockup and labelled as such. Nothing is sent.
