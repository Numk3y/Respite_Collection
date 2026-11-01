Background pictures. Letter case doesn't matter, and .png, .jpg, .jpeg or .webp all work.

  HomeBg.png (or home.png)  - the Home screen's stage, behind the featured character
                              (replaces the drawn "Mirror Room"; the card, pedestal and light motes stay on top)

  <ChapterName>.png         - battle background for every map in that chapter. The file name is the chapter's
                              name without spaces: Chapter 1 "Poppy Street" -> PoppyStreet.png (1-1 to 1-5).
                              Chapter names live in Scripts/autoload/terms.gd (CHAPTER_NAMES).

  battle.png                - fallback battle background for chapters without their own picture

A single map can override all of this with its own picture: set "Background" on the map in Data/stages/.
Pictures are scaled to cover the area and centred, so wide landscape images (16:9) fit best.
After adding or changing a picture, re-export the web build to see it on the site.
