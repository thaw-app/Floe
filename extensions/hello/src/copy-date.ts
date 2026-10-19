import { Clipboard, showHUD } from "@raycast/api";

export default async function Command() {
  // en-CA writes the local date as YYYY-MM-DD; toISOString would give the UTC date.
  const today = new Date().toLocaleDateString("en-CA");
  await Clipboard.copy(today);
  await showHUD(`Copied ${today}`);
}
