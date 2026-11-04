Pool templates: starting points for new recruit pools. The game does NOT load this folder.

pickup_template.tres - a Pick Up banner (the old Testing Pool): two friends ticked "featured" show large on the
banner (one featured = the solo layout, two = side by side), everyone else drifts by behind them.

To make a new Pick Up pool:
1. Duplicate pickup_template.tres into Data/pools/ and rename it (e.g. pickup_quinn.tres).
2. In the Inspector: give it its own id (e.g. pickup_quinn) and display name, a theme colour or banner picture.
3. Edit the entries: add the limited friend(s), tick "featured" on the ones to show, raise an entry's weight for a
   rate-up within its rarity.
Pools in Data/pools/ show up in Recruit in file-name order. A pool with nothing featured uses the Common layout
(every SSR large at the back, the SRs as a slideshow in front), like common_pool.tres.
