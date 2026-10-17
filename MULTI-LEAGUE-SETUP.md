# Arena League Hub setup

The site uses the existing Supabase project configured in `online-config.js`. Keep its public project URL and publishable key in that file; never put a service-role key in browser code.

## Database setup

1. In the existing Supabase project, confirm the `public.leagues` table is present. If it is missing, run `supabase-multileague-setup.sql` once.
2. Before changing a production database, make a Supabase backup/export of the existing `leagues` table and verify it is restorable.
3. Run `supabase-player-accounts.sql` to add account roles, unique league codes, player memberships, team branding, and logo storage policies.
4. In **Authentication → URL Configuration**, allow the deployed GitHub Pages address as a site URL and redirect URL: `https://kiwaloshafic720-cmd.github.io/dls-arena-tracker/`.

The player accounts migration adds a `join_code` column and backfills a code for each existing league. It does not update, copy, or delete `leagues.state`. Existing scores, match history, and standings therefore remain in their existing state document. Player memberships and logos are stored separately. The migration makes no changes to the older `tournament_state` data.

## Roles and permissions

- The configured platform owner is registered in the private `platform_owners` table.
- The user who owns a league is its league admin and can manage its roster and results.
- A signed-in player claims one unclaimed roster entry with the unique league code. The league admin approves the claim before the player can change that team's badge or logo.
- Players have no update policy on `leagues`, so they cannot change scores, matches, wins, losses, points, or standings.
- Custom logos use the dedicated public `dls-team-logos` bucket. Uploads are limited to PNG, JPEG, and WebP images under 2 MB; storage rules restrict writes to the team owner or league admin.

## Deploy

After reviewing the local changes and applying the database migration, publish the updated static files to GitHub Pages. Publishing is a separate step; these files do not deploy or alter production data by themselves.
