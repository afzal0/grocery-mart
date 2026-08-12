# Shopkeeper field survey

Field research instrument for Grocery-Mart supply-side validation. Single self-contained
HTML file — no build step, no dependencies, no network calls.

## Why it's built this way

Interviews happen standing up in a shop, on a phone, often on patchy mobile data. So:

- **Offline by design.** Nothing is transmitted. Every keystroke autosaves to `localStorage`,
  so a dropped connection or an accidental back-swipe never costs an interview.
- **Resumable.** Reloading mid-interview picks up exactly where you left off.
- **Export-driven.** Responses accumulate on the device; the interviewer downloads CSV or
  JSON at the end of the day.

## Checking responses

**On the device that collected them** — tap the `N saved` chip in the top-right at any
time. It shows every interview recorded on that device, a running read on the decisive
questions, and the CSV/JSON export buttons.

**Across several interviewers** — each device holds only its own responses, so fieldwork
produces one CSV per device. Collect them and merge:

```bash
./merge-responses.py ~/Downloads/grocery-mart-*.csv -o merged.csv
```

That deduplicates by interview id (in case a device's export is collected twice), then
prints the decisive-question distributions and the gap between stated intent (`I1`) and
the one costly commitment (`I3`).

## Data handling

Responses live only in the browser's `localStorage` on the interviewer's device. Question
**I5 collects a name and phone or email**, which is personal information under the Privacy
Act. Export to CSV, move it into your own storage, then clear the device.

Nothing leaves the device on its own — there is no backend, no analytics, no third-party
script. That is deliberate: it keeps the instrument out of scope for any data-transfer
question while fieldwork is running.

## Structure

| Section | Covers |
|---|---|
| Setup | Interviewer and area, entered once per session |
| S | Screener with hard termination |
| A | Store profile |
| B | Operations and data readiness |
| C | Customers and local competition |
| D | Existing platform experience |
| E | Reaction to price comparison |
| F | Commission and pricing sensitivity |
| G | Fulfilment capability |
| H | Partnership and exclusivity |
| I | Commitment |
| J | Open questions |
| K | Optional sensitive details |

Six questions are marked **decisive** in the UI — `B3`, `B9`, `E2`, `E3`, `E7`, `I3`. If
those come back badly, the model needs rethinking regardless of how warm the rest is.

## Run locally

```bash
python3 -m http.server 4173 --directory apps/research-survey
# http://localhost:4173
```

## Sharing with the field team

The page holds **no respondent data** — it is a blank form, and every answer stays on the
interviewer's own device. So what a leaked URL exposes is the questionnaire design (which
does reveal commission thresholds and the exclusivity plan), not anyone's personal
information. That sets the bar at "not publicly discoverable" rather than "needs real auth".

`robots.txt` and a `noindex` meta tag are already in place, so the page will not be indexed
wherever it is hosted.

For access control on top of that, use Vercel's Deployment Protection — either **Vercel
Authentication** (restricted to members of your Vercel team) or **Password Protection**
(one shared password, the practical choice for contract interviewers who are not on the
team). Check current plan gating in the Vercel dashboard before relying on either.

Do not add a client-side passcode to this file. The source is public, so any check in the
page is theatre — it would keep out casual visitors while giving you false confidence.

## Deploy

```bash
npx vercel deploy --prod apps/research-survey
```

Static, so there is no build and no environment variable to set.

## Editing the questions

The whole instrument is one `SECTIONS` array near the top of the `<script>` block in
`index.html`. Question types: `single`, `multi`, `scale`, `text`, `longtext`, `number`.

- `critical: true` adds the amber rule and the "decisive" tag.
- `why:` renders the amber explainer under the question.
- `showIf: function (a) { ... }` handles skip logic against the answer map.
- `terminate: true` on an option ends the interview as a screen-out.

Adding a question automatically adds its column to the CSV export — no other change needed.
