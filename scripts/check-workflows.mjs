#!/usr/bin/env node
// Fails when a GitHub Actions job that runs on a self-hosted runner is given a secret. A
// self-hosted runner that keeps running between jobs lets a process one job leaves behind read
// a later job's secrets, so jobs with secrets belong on GitHub's hosted runners.
//
//   node scripts/check-workflows.mjs [repo]      (default: the current folder)
//
// Exits 1 and names each job (file:line, the secrets it gets), 0 when there are none.
//
// A job counts as self-hosted when its block says self-hosted anywhere (runs-on, a matrix). A
// job whose runs-on is an expression with no runner name in its block can't be placed, so it
// fails too: name the runners in a matrix or the block. A secret is any secrets.NAME,
// secrets[...] or toJSON(secrets) the job's block or the workflow's top level (env: there
// reaches every job) mentions, except secrets.GITHUB_TOKEN, which every job gets anyway.
// Comments don't count.
//
// It reads YAML as lines and indentation, which holds for workflows written the usual way
// (jobs: at the left edge, job names two spaces in). It can't be tricked into passing a job it
// can see, but a workflow laid out differently may need a look by hand.

import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

const repo = process.argv[2] ?? ".";
const dir = join(repo, ".github", "workflows");
if (!existsSync(dir)) {
  console.log("check-workflows: no workflows");
  process.exit(0);
}

const uncomment = (line) => line.replace(/(^|\s)#.*$/, "");
const secretsIn = (text) =>
  [...text.matchAll(/\bsecrets\s*(\.\s*([A-Za-z_][A-Za-z0-9_-]*)|\[[^\]]*\]|\))/g)]
    .map((m) => (m[2] ? `secrets.${m[2]}` : `secrets${m[1]}`))
    .filter((s) => s !== "secrets.GITHUB_TOKEN");
const RUNNER_NAMES = /\b(self-hosted|ubuntu-|macos-|windows-)/;

const problems = [];
const files = readdirSync(dir).filter((f) => /\.ya?ml$/.test(f)).sort();
for (const file of files) {
  const lines = readFileSync(join(dir, file), "utf8").split("\n").map(uncomment);
  const jobsAt = lines.findIndex((l) => /^jobs:\s*$/.test(l));
  if (jobsAt < 0) continue;

  // Jobs: a name two spaces in, up to the next name or the next key at the left edge.
  const jobs = [];
  let topLevel = lines.slice(0, jobsAt).join("\n");
  for (let i = jobsAt + 1; i < lines.length; i++) {
    const name = lines[i].match(/^ {2}([A-Za-z_][A-Za-z0-9_-]*):\s*$/);
    if (name) jobs.push({ name: name[1], line: i + 1, body: [] });
    else if (/^\S/.test(lines[i])) {
      topLevel += "\n" + lines.slice(i).join("\n");
      break;
    } else if (jobs.length) jobs[jobs.length - 1].body.push(lines[i]);
  }

  const everyJob = secretsIn(topLevel);
  for (const job of jobs) {
    const body = job.body.join("\n");
    const runsOn = job.body.find((l) => /^\s{4}runs-on:/.test(l)) ?? "";
    const where = `${join(".github", "workflows", file)}:${job.line}: job ${job.name}`;
    if (/\$\{\{/.test(runsOn) && !RUNNER_NAMES.test(body)) {
      problems.push(`${where} runs on ${runsOn.trim().replace(/^runs-on:\s*/, "")}, which can't be placed; name its runners`);
      continue;
    }
    if (!/self-hosted/.test(body)) continue;
    const given = [...new Set([...everyJob, ...secretsIn(body)])];
    if (given.length) problems.push(`${where} runs on a self-hosted runner and is given ${given.join(", ")}`);
  }
}

for (const p of problems) console.log(p);
if (problems.length) process.exit(1);
console.log(`check-workflows: no self-hosted job is given a secret (${files.length} workflow${files.length === 1 ? "" : "s"})`);
