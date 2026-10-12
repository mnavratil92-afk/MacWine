// Reads every discussion in the "Compatibility" category and writes ratings.json:
//   { "updated": "...", "games": { "steam/271590": { "average": 4.5, "count": 2, "latestVersion": "0.9.13" } } }
// A report is a discussion whose body contains the lines MacWine pre-fills:
//   Game: steam/271590 (Grand Theft Auto V Legacy)
//   Rating: 4/5
//   MacWine: 0.9.13 · macOS 27.0 · Apple M1 Pro
// Only the newest report of each GitHub user per game counts.
const fs = require('fs');

module.exports = async ({ github, context, core }) => {
  const { owner, repo } = context.repo;
  const cat = await github.graphql(`query($owner:String!,$repo:String!){ repository(owner:$owner,name:$repo){ discussionCategory(slug:"compatibility"){ id } } }`, { owner, repo });
  const categoryId = cat.repository.discussionCategory && cat.repository.discussionCategory.id;
  const latest = new Map();   // "user|game" -> report
  if (categoryId) {
    let cursor = null;
    do {
      const page = await github.graphql(`query($owner:String!,$repo:String!,$cat:ID!,$after:String){
        repository(owner:$owner,name:$repo){ discussions(first:100, after:$after, categoryId:$cat){
          pageInfo{ hasNextPage endCursor }
          nodes{ body updatedAt author{ login } } } } }`, { owner, repo, cat: categoryId, after: cursor });
      const d = page.repository.discussions;
      for (const n of d.nodes) {
        const game = /^\s*Game:\s*([a-z]+)\/([^\s()]+)/mi.exec(n.body || '');
        const rating = /^\s*Rating:[^\n]*?\b([0-5])\s*\/\s*5\b/mi.exec(n.body || '');
        if (!game || !rating || !n.author) continue;
        const version = /^\s*MacWine:\s*([0-9][0-9.]*)/mi.exec(n.body || '');
        const key = `${game[1].toLowerCase()}/${game[2]}`;
        const id = `${n.author.login}|${key}`;
        const prev = latest.get(id);
        if (!prev || prev.updatedAt < n.updatedAt) latest.set(id, { key, stars: Number(rating[1]), version: version ? version[1] : null, updatedAt: n.updatedAt });
      }
      cursor = d.pageInfo.hasNextPage ? d.pageInfo.endCursor : null;
    } while (cursor);
  } else {
    core.warning('Discussion category "compatibility" not found - writing an empty ratings.json');
  }
  const games = {};
  for (const r of latest.values()) {
    const g = games[r.key] || (games[r.key] = { sum: 0, count: 0, latestVersion: null, latestAt: '' });
    g.sum += r.stars; g.count += 1;
    if (r.version && r.updatedAt > g.latestAt) { g.latestVersion = r.version; g.latestAt = r.updatedAt; }
  }
  const out = {};
  for (const [k, g] of Object.entries(games)) out[k] = { average: Math.round((g.sum / g.count) * 10) / 10, count: g.count, latestVersion: g.latestVersion };
  fs.writeFileSync('ratings.json', JSON.stringify({ updated: new Date().toISOString(), games: out }, null, 1));
  core.info(`${Object.keys(out).length} games, ${latest.size} reports`);
};
