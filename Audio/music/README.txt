Background music. Use .ogg (best for the web build), .mp3 or .wav. Letter case doesn't matter.

  Home.ogg              - the Home screen (also the starter pick); Homepage.ogg works too

  <ChapterName>.ogg     - battles in that chapter. The file name is the chapter's name without spaces,
                          the same as its background: Chapter 1 "Poppy Street" -> PoppyStreet.ogg (1-1 to 1-5).
                          Chapter names live in Scripts/autoload/terms.gd (CHAPTER_NAMES).

  battle.ogg            - battles in chapters without their own track (optional)

Every track loops. The song only changes when the player goes to a screen with a different track:
replaying a map ("Again") keeps the chapter song playing where it was, and it only switches back to
Home.ogg when the player returns to the Home screen. Coming back to a song picks it up where it left off
(e.g. the Home song continues after a battle). If a track is missing, whatever is playing keeps going.
Settings (Home header) has a music volume slider, remembered in the save.
After adding or changing a track, re-export the web build to hear it on the site.
