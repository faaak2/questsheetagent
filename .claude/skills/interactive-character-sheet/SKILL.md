---
name: interactive-character-sheet
description: |
  **Interactive Character Sheet Generator**: Extracts character sheets from gamebook PDFs or images (PNG/JPG) and builds fully interactive, browser-based HTML character sheets with dice rollers, stat trackers, and save/load functionality.
  - MANDATORY TRIGGERS: character sheet, gamebook, interactive sheet, RPG sheet, game book character, tabletop character tracker, player sheet, agent profile
  - Use this skill whenever the user wants to create a digital/interactive version of a paper character sheet from ANY tabletop RPG, gamebook, or solo adventure game
  - Also trigger when the user has a folder of character sheets to batch-process into interactive HTML files
  - Works with both PDF files (extracts the sheet pages) and standalone images (PNG/JPG) of character sheets
---

# Interactive Character Sheet Generator

You turn paper character sheets from gamebooks and tabletop RPGs into polished, fully interactive browser-based HTML tools. The input can be a PDF containing a character sheet or a direct image (PNG/JPG) of one.

## Why this skill exists

Paper character sheets get erased, smudged, and lost. An interactive HTML version lets players track stats with click buttons, roll dice inline, and save/load their progress as JSON — all from a phone or laptop at the table. The challenge is that every game system is different, so you need to carefully analyze each sheet before building anything.

## Workflow

### Phase 1: Analyze the source

**If the input is a PDF:**
1. Use `pdfplumber` or `pypdf` to extract text from all pages
2. Search for character sheet pages — look for keywords like "character", "sheet", "profile", "stats", "vitality", "health", "strength", "skill", "equipment"
3. Also check the last 20% of pages — character sheets are almost always in the back
4. Extract the full text of sheet pages AND the rulebook pages that explain the game mechanics (skills, combat, items, etc.)

**If the input is an image (PNG/JPG):**
1. Read the image visually — Claude can see images natively
2. Identify every field, grid, tracker, checkbox, and text area on the sheet
3. Ask the user for the rulebook or game rules if not provided, since you'll need the mechanics to make the sheet functional (what do the stats do? how does combat work? what are the valid values?)

### Phase 2: Map the sheet structure

Before writing any code, create a complete inventory of every element on the sheet. Character sheets across different games share common patterns:

**Point trackers** — numeric values with a current and max (HP, MP, Vitality, Energy, Stamina, etc.). These need +/- buttons, a max field, and ideally a visual bar.

**Skills/Attributes** — named stats with numeric scores (Strength, Dexterity, Stealth, etc.). These need adjustable values with +/- controls.

**Toggle grids** — numbered or lettered cells the player circles/checks to track which items they've acquired (memories, achievements, insights, spells known). These need clickable cells that toggle on/off.

**Inventory lists** — open-ended lists where players write in items (equipment, weapons, armor, spells). These need add/remove functionality with text inputs.

**Selection fields** — choices from a fixed list (class, specialization, race). These need dropdowns populated with the valid options and their rule descriptions.

**Active equipment slots** — a highlighted single item from the inventory (active weapon, active armor). These need a text field plus any relevant sub-stats (damage, CP bonus, armor value).

**Counters** — simple numeric counters for consumables (meals, potions, ammo, gold). These need +/- buttons and sometimes a "use" button that applies an effect (e.g., eating a meal restores HP).

**Free text** — notes sections for the player to write whatever they want. These need a resizable textarea.

**Name/identity fields** — character name, player name, class, level. These need simple text inputs.

Map every element on the sheet to one of these patterns. If something doesn't fit, invent a suitable UI pattern for it.

### Phase 3: Extract the game rules

This is critical for making the sheet actually useful during play. Read the rulebook pages and extract:

- **Starting values** for all stats (e.g., "You begin with 10 HP and 5 in each skill")
- **Dice mechanics** — what dice does the game use? (1D6, 2D6, D20, percentile, etc.)
- **Skill check rules** — how are checks resolved? (roll under? roll + modifier vs target?)
- **Combat rules** — what stats are used? how is damage calculated? are there rounds?
- **Consumable effects** — what happens when you use a meal/potion/item?
- **Special abilities** — any specializations, classes, or abilities with mechanical effects
- **Equipment rules** — weapon stats, armor rules, unarmed penalties

These rules inform what helper tools to build into the sheet (dice roller, skill check calculator, combat tracker, etc.).

### Phase 4: Build the interactive HTML

Create a single self-contained HTML file. Everything — CSS, JS, HTML — goes in one file so it's portable and easy to share.

#### Design principles

- **Dark theme** — dark background (#0d1117), subtle borders, colored accents for different stat types. This looks great on screens and reduces eye strain at the gaming table.
- **Card-based layout** — each section of the sheet is a card with a title, organized in a responsive CSS grid (2 columns on desktop, 1 on mobile).
- **Color coding** — use distinct colors for different stat types (red for health, blue for energy/mana, green for stealth/nature, purple for magic/sixth sense, gold for memory/XP).
- **Monospace numbers** — use a monospace font for all numeric displays so digits don't jump around.
- **Responsive** — must work on phones. Use CSS grid with `@media` breakpoints.
- **No external dependencies** — no CDNs, no frameworks. Pure HTML/CSS/JS.

#### Required built-in tools

Every interactive sheet must include:

1. **Dice roller** — buttons for each die type the game uses (1D6, 2D6, D20, etc.) with visual results and a roll history
2. **Auto-save** — save state to localStorage on every change, load on page open
3. **Export/Import** — save character as JSON file, load from JSON file (for backup and sharing)
4. **Reset button** — create a new character with default starting values (with confirmation dialog)

#### Game-specific tools (include when the rules support them)

- **Skill check calculator** — select skill, optionally boost with EP/other resource, roll dice, show pass/fail result
- **Combat tracker** — input enemy stats, roll hero+enemy dice, calculate damage, auto-apply VP loss
- **Consumable "use" buttons** — e.g., "Eat a Meal" that auto-applies the healing effect
- **Resource spending** — when a mechanic costs a resource (EP for skill checks, MP for spells), the tool should auto-deduct it

#### HTML structure template

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>[Game Name] — Character Sheet</title>
  <style>
    /* Dark theme CSS variables, layout, cards, buttons, inputs, etc. */
  </style>
</head>
<body>
  <header><!-- Game logo/title, save/load/reset buttons --></header>
  <div class="container">
    <!-- Name fields (full width) -->
    <!-- Point trackers (VP/EP side by side) -->
    <!-- Skills grid (equal columns) -->
    <!-- Consumables and resource counters -->
    <!-- Toggle grids (memories, achievements) -->
    <!-- Equipment and inventory lists -->
    <!-- Active weapon/armor -->
    <!-- Specializations/abilities -->
    <!-- Dice roller and game tools -->
    <!-- Notes textarea (full width) -->
  </div>
  <script>
    /* State management, render functions, event handlers, save/load */
  </script>
</body>
</html>
```

#### State management pattern

Use a single `state` object that holds all character data. Every UI change updates `state` and calls `saveState()`. On page load, call `loadState()` to restore from localStorage.

```javascript
const STATE_KEY = 'gameNameSheet';
let state = getDefaultState();

function getDefaultState() {
  return { /* all fields with starting values from the rules */ };
}

function loadState() {
  try {
    const saved = localStorage.getItem(STATE_KEY);
    if (saved) state = { ...getDefaultState(), ...JSON.parse(saved) };
  } catch(e) {}
}

function saveState() {
  try { localStorage.setItem(STATE_KEY, JSON.stringify(state)); } catch(e) {}
}

function renderAll() { /* update every UI element from state */ }
```

### Phase 5: Verify

After generating the HTML file:
1. Check that every field from the original sheet is represented
2. Verify starting values match the rulebook
3. Confirm dice mechanics match the game rules
4. Test that skill checks / combat trackers use the correct formulas
5. Make sure export/import and reset work correctly

### Phase 6: Deliver

Save the final HTML file to the user's workspace folder. Summarize what you built — the game name, the fields included, the built-in tools, and any game-specific features. Mention anything from the original sheet that you couldn't replicate or had to adapt.

## Batch processing

When the user provides a folder of multiple character sheets:
1. List all PDF and image files in the folder
2. Process each one sequentially through the full workflow
3. Name output files based on the game name: `{game_name}_character_sheet.html`
4. At the end, provide a summary of all sheets created

## Common pitfalls

- **Don't guess mechanics** — if the PDF/image doesn't contain enough rule information to build functional tools (dice roller, combat tracker), ask the user for the rulebook or skip those tools and note what's missing.
- **Don't hardcode specific values** — the sheet should work for any character build, not just the example in the rulebook.
- **Toggle grids must be accurate** — count every cell label exactly as shown on the sheet. Getting the insight/memory/spell grid wrong makes the sheet useless.
- **Test the math** — if the game has combat formulas (CPs + roll - penalty = total), make sure your JavaScript implements them correctly.
