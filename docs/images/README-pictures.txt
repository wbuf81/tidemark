Pictures the README refers to. All of them are drawn by the render mode (demo data, the fixed
render moment) in two files, <name>-light.png and <name>-dark.png, in this folder, plus two GIFs.
Nothing is captured by hand. To remake them after a UI change, run:

    scripts/make-readme-images.sh

(it runs `swift run Tidemark --render` into a temp folder, copies the readme-* pictures here,
builds the GIFs with ffmpeg and deletes the temp folder). The pictures come from
Sources/Tidemark/Render/ReadmeShots.swift.

hero              A desktop on the sky: the menu bar's batteries, the window on Usage, the widget beside a
                  Dock; 980 points (1960 px) wide
feature-<name>    The "What it does" tiles, all 880 x 560 points (1760 x 1120 px), the subject centred on the
                  sky: tide, status, battery, details, usage, week, report, trends, notch, private
step-download     Illustration: the Tidemark icon and an arrow into the Applications folder
step-not-opened   Illustration: an alert-style card, "Tidemark" Not Opened, with Done and Move to Bin
step-open-anyway  Illustration: a Privacy & Security row with the Open Anyway button highlighted
step-reads        First run, step 2: What Tidemark reads (the real view)
step-plan-limits  First run, step 3: Show your plan's limits? with the warning (the real view)
step-widget       The widget beside a Dock
widget-status.gif Light only: Claude Code's status Idle, Thinking, Working, Needs you, Done on the plan's
                  chip, plan cards unchanged; 900 px wide, 1.5 s a frame
click-a-plan.gif  Light only: the widget alone for 1.5 s, then Harbor Labs's details card open above it
                  for 2.5 s; 640 px wide

The three macOS pictures are drawings in Tidemark's palette, marked "Illustration"; they are not
copies of Apple's screens, so they never need recapturing for a new macOS.
Only <name>-light.png, <name>-dark.png, the two GIFs and this file are exported to the public
repository (scripts/export-allowlist.txt).
