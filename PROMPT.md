Build me a native Mac clipboard manager called ClipKeeper that feels
like Apple should have included it. Make it beautiful, fast, and
useful enough that I keep it installed. I currently use iClip, which
does some of what I want but 1. doesn't render rich types, 2. doesn't
let me use a key like CMD-Shift-V to bring it up and then cursor
keys/ESC/Enter to navigate it. I want my hands to stay on the keyboard
when using this app. Nate B Jones created an app called Ledge which is
partway to what I'm looking for, but 1. doesn't render types like
Markdown, 2. doesn't do cursor navigation, 3. copying into the
clipboard doesn't always put the clipboard contents into a slot. In
particular it needs to show me representation of text, images, links,
and be hotkey accessible with assignable hotkeys (by default, Copy
fills the top slot, and CMD-Shift-V brings up the UI and lets me use
keyboard navigation as I've described). A little shelf should slide
out from the right side of the screen with everything ready for me to
grab and use.

Support "clip sets" like iClip does, and make the left/right cursor
keys navigate between them. Support the cursor keys up/down as well as
emacs keybindings (^N/^P/^B/^F), and a UI to customize
keybindings. Also, allow the user to save a file with the contents of
a cell (e.g., save an .md file for markdown or rich text content, a
.png for an image, etc). Make sure you handle all the clipboard
content types that make sense for an app like this.

For contents that look like code (bash, Python, typescript, etc)
render in a Markdown code block, so the preview is pretty.

For textual content let the user edit the value; for images let them
crop.

Think about this spec and let's talk through it and clarify before
proceeding with implementation.
