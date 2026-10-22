# The one definition of what the sensitive-text checks let through. Sourced by
# scan-sensitive.sh (the commit guard) and scripts/grep-gate.sh (the export gate).
# A match is fine if the matched text contains one of these (extended regex, any case).
# Retina image names such as icon_16x16@2x.png (iconutil needs them) are file names, not email addresses.
allow='00000000-0000-|8AD323F0-8465-42C6-98BD-6E670027E1DC|@example\.(com|org)|noreply@anthropic\.com|@users\.noreply\.github\.com|/Users/you/|@[1-3]x\.(png|jpe?g)$'
