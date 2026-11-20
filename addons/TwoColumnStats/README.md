# Two Column Stats

A World of Warcraft: Forever addon that shows the character sheet's stats in
two columns, so you can see them all without scrolling.

- Uses the game's own stat functions, so values and tooltips match the default sheet.
- Widens the character window while the stats pane is open, and puts it back
  on other tabs (Reputation, Skills and so on).
- Keeps the pane's background art seamless across the wider window.
- In combat, values the game hides from addons keep showing their last value
  until combat ends.

## Commands

| Command      | What it does                                           |
| ------------ | ------------------------------------------------------ |
| `/tcs`       | Switch between two columns and the default stats sheet |
| `/tcs debug` | List the background textures, for bug reports          |

## Known limitations

- Panels opened beside the character window (like the spellbook) are placed as
  if the window were its normal width, so they can overlap it slightly.
