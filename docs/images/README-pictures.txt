Pictures the README refers to. All of them are drawn by the render mode (demo data, the fixed
render moment) in two files, <name>-light.png and <name>-dark.png, in this folder, plus one GIF.
Nothing is captured by hand. To remake them after a UI change, run:

    scripts/make-readme-images.sh

(it runs `swift run Tidemark --render` into a temp folder, copies the readme-* pictures here,
builds the GIF with ffmpeg and deletes the temp folder). The pictures come from
Sources/Tidemark/Render/ReadmeShots.swift.

hero              Tidemark's window (Week) with the widget beside a Dock; 880 points (1760 px) wide
step-download     Illustration: the Tidemark icon and an arrow into the Applications folder
step-not-opened   Illustration: an alert-style card, "Tidemark" Not Opened, with Done and Move to Bin
step-open-anyway  Illustration: a Privacy & Security row with the Open Anyway button highlighted
step-reads        First run, step 2: What Tidemark reads (the real view)
step-plan-limits  First run, step 3: Show your plan's limits? with the warning (the real view)
step-widget       The widget beside a Dock
widget-status.gif Light only: the widget's Claude Code status Idle, Thinking, Working, Needs you,
                  Done, with the plan cards unchanged; 900 px wide, under 1.5 MB

The three macOS pictures are drawings in Tidemark's palette, marked "Illustration"; they are not
copies of Apple's screens, so they never need recapturing for a new macOS.
Only <name>-light.png, <name>-dark.png, widget-status.gif and this file are exported to the public
repository (scripts/export-allowlist.txt).
