# Arena League Hub database setup

The site uses the existing Supabase project configured in `online-config.js`. Keep that file private and unchanged.

## Activate accounts and league storage

1. Open the existing Supabase project and go to **SQL Editor**.
2. Open `supabase-multileague-setup.sql` from this repository, copy its full contents into a new SQL query, and run it.
3. In **Authentication → URL Configuration**, make sure the deployed GitHub Pages address is allowed as a site URL and redirect URL:
   `https://kiwaloshafic720-cmd.github.io/dls-arena-tracker/`
4. Open the site over HTTPS, create/sign into an account, and create a league.

The SQL creates a new `leagues` table. Signed-in accounts can read or change only rows they own. A player link contains a random share code that opens one league read-only; visitors cannot list leagues. The old `tournament_state` table and its data are not changed or imported.

New accounts may need to verify their email before signing in. Supabase Auth email settings control that behavior. The app also uses Supabase Auth password reset email delivery.
