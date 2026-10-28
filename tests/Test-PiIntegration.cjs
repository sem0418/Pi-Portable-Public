/* Local, dependency-free protocol fixture. No external model, no API costs.
 * Validates real Pi discovery, slash expansion and (on Windows) native shell tools.
 * This deterministic fixture does NOT validate an LLM's automatic skill choices.
 */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const http = require('node:http');
const crypto = require('node:crypto');
const { spawn } = require('node:child_process');
const argv = process.argv.slice(2);
function option(name, fallback) { const i = argv.indexOf(name); return i < 0 ? fallback : argv[i + 1]; }
const root = path.resolve(option('--root', path.join(__dirname, '..')));
const pi = path.resolve(option('--pi', path.join(root, 'runtime/pi/pi.exe')));
const output = path.resolve(option('--output', path.join(root, 'data/reports/test-pi-integration.json')));
const windows = process.platform === 'win32';
const quick = argv.includes('--quick-windows');
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'PiPortable-测试 空格-'));
const agent = path.join(temp, 'agent');
const reports = path.join(temp, 'reports');
const workspace = path.join(temp, 'workspace');
for (const d of [agent, reports, workspace, path.join(temp, 'home'), path.join(temp, 'sessions')]) fs.mkdirSync(d, { recursive: true });
fs.cpSync(path.join(root, 'data/agent/skills'), path.join(agent, 'skills'), { recursive: true });
fs.writeFileSync(path.join(workspace, '测试 file.txt'), 'local integration fixture');
const skills = {
  'windows-diagnostics': 'Collect-Diagnostics.ps1',
  'malware-triage': 'Collect-MalwareTriage.ps1',
  'file-organizer': 'Invoke-FileOrganizer.ps1',
  'network-troubleshooting': 'Collect-Network.ps1',
  'disk-health': 'Collect-DiskHealth.ps1',
  'windows-repair': 'Invoke-WindowsRepair.ps1'
};
const results = [];
let active = null;
function run(args, env, input) {
  return new Promise((resolve, reject) => {
    const child = spawn(pi, args, { cwd: workspace, env, stdio: ['pipe', 'pipe', 'pipe'], windowsHide: true });
    let stdout = '', stderr = '';
    const timeout = setTimeout(() => { child.kill(); reject(new Error('Pi integration observation timed out')); }, args.includes('rpc') ? 45000 : (quick ? 45000 : (windows ? 240000 : 45000)));
    child.stdout.setEncoding('utf8'); child.stderr.setEncoding('utf8');
    child.stdout.on('data', x => {
      stdout += x;
      // RPC is persistent. Wait for both responses before closing input, so EOF
      // shutdown cannot race command handling on native Windows.
      if (args.includes('rpc') && !child.stdin.writableEnded) {
        const lines = stdout.split(/\r?\n/).filter(Boolean);
        if (lines.some(l => { try { return JSON.parse(l).id === 'commands'; } catch { return false; } }) &&
            lines.some(l => { try { return JSON.parse(l).id === 'state'; } catch { return false; } })) child.stdin.end();
      }
    }); child.stderr.on('data', x => { stderr += x; });
    child.on('error', e => { clearTimeout(timeout); reject(e); });
    child.on('exit', code => { clearTimeout(timeout); code === 0 ? resolve({ stdout, stderr }) : reject(new Error(`Pi exit ${code}: ${stderr.slice(0, 1200)}`)); });
    if (args.includes('rpc')) child.stdin.write(input || '');
    else child.stdin.end(input || '');
  });
}
function assert(condition, message) { if (!condition) throw new Error(message); }
function psQuote(x) { return "'" + x.replace(/'/g, "''") + "'"; }
const server = http.createServer((req, res) => {
  let raw = '';
  req.on('data', b => { raw += b; if (raw.length > 8 * 1024 * 1024) req.destroy(); });
  req.on('end', () => {
    try {
      const body = JSON.parse(raw);
      if (!active) throw new Error('Unexpected local provider request');
      const text = JSON.stringify(body.messages);
      const declarations = body.tools || [];
      active.advertised = text.includes('<available_skills>') && Object.keys(skills).every(s => text.includes(s));
      active.expanded = body.messages.some(m => m.role === 'user' && JSON.stringify(m.content).includes(`<skill name=\\"${active.skill}\\"`));
      // JSON.stringify of strings uses escaped quotes; inspect raw message content too.
      active.expanded ||= body.messages.some(m => m.role === 'user' && (typeof m.content === 'string' ? m.content : JSON.stringify(m.content)).includes(`<skill name="${active.skill}"`));
      const names = declarations.map(t => t.function && t.function.name);
      active.bash = names.includes('bash'); active.powershell = names.includes('powershell');
      const hasToolResult = body.messages.some(m => m.role === 'tool');
      const base = { id: 'chatcmpl-local-fixture', object: 'chat.completion.chunk', created: Math.floor(Date.now()/1000), model: 'local-fixture' };
      res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache' });
      if (windows && !hasToolResult) {
        const helper = path.join(agent, 'skills', active.skill, 'scripts', skills[active.skill]);
        let command = `& ${psQuote(helper)} -OutputDirectory ${psQuote(reports)} -PassThru | ConvertTo-Json -Depth 5`;
        if (active.skill === 'file-organizer') command = `& ${psQuote(helper)} -Mode Scan -Path ${psQuote(workspace)} -OutputDirectory ${psQuote(reports)} -PassThru | ConvertTo-Json -Depth 5`;
        if (quick) command = "Write-Output 'portable-native-fixture'";
        const delta = { role: 'assistant', tool_calls: [{ index: 0, id: 'call_fixture', type: 'function', function: { name: 'powershell', arguments: JSON.stringify({ command, timeout: 120 }) } }] };
        res.write('data: ' + JSON.stringify({ ...base, choices: [{ index: 0, delta, finish_reason: null }] }) + '\n\n');
        res.write('data: ' + JSON.stringify({ ...base, choices: [{ index: 0, delta: {}, finish_reason: 'tool_calls' }] }) + '\n\n');
      } else {
        res.write('data: ' + JSON.stringify({ ...base, choices: [{ index: 0, delta: { role: 'assistant', content: 'Local protocol fixture completed.' }, finish_reason: null }] }) + '\n\n');
        res.write('data: ' + JSON.stringify({ ...base, choices: [{ index: 0, delta: {}, finish_reason: 'stop' }], usage: { prompt_tokens: 20, completion_tokens: 5, total_tokens: 25 } }) + '\n\n');
      }
      res.end('data: [DONE]\n\n');
    } catch (e) { if (active) active.error = e.message; res.writeHead(500); res.end(JSON.stringify({ error: { message: e.message } })); }
  });
});
(async () => {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const token = crypto.randomBytes(24).toString('hex');
  fs.writeFileSync(path.join(agent, 'models.json'), JSON.stringify({ providers: { 'portable-local-test': { baseUrl: `http://127.0.0.1:${server.address().port}/v1`, api: 'openai-completions', apiKey: token, models: [{ id: 'local-fixture', reasoning: false, input: ['text'], contextWindow: 128000, maxTokens: 4096, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 } }] } } }));
  fs.writeFileSync(path.join(agent, 'settings.json'), JSON.stringify({ defaultProvider: 'portable-local-test', defaultModel: 'local-fixture', defaultTools: windows ? ['read','bash','powershell','edit','write'] : ['read','bash','edit','write'], enableSkillCommands: true, shellPath: windows ? path.join(root, 'tools/git/bin/bash.exe') : '/bin/bash' }));
  const env = { ...process.env, PI_PORTABLE_ROOT: temp, PI_CODING_AGENT_DIR: agent, PI_CODING_AGENT_SESSION_DIR: path.join(temp, 'sessions'), PI_PACKAGE_DIR: path.dirname(pi), HOME: path.join(temp, 'home'), USERPROFILE: path.join(temp, 'home') };
  try {
    const rpc = await run(['--mode', 'rpc', '--no-session'], env, '{"id":"commands","type":"get_commands"}\n{"id":"state","type":"get_state"}\n');
    const lines = rpc.stdout.split(/\r?\n/).filter(Boolean).map(x => JSON.parse(x));
    const reply = lines.find(x => x.id === 'commands' && x.success);
    assert(reply, 'RPC command discovery failed');
    for (const skill of Object.keys(skills)) assert(reply.data.commands.some(c => c.name === `skill:${skill}` && c.source === 'skill'), `Skill was not discovered: ${skill}`);
    results.push({ name: 'Official Pi RPC discovers all six user skills', status: 'passed' });
    for (const skill of Object.keys(skills)) {
      active = { skill, advertised: false, expanded: false, bash: false, powershell: false };
      try {
        const sessionArgs = skill === 'windows-diagnostics' ? [] : ['--no-session'];
        const r = await run(['--mode','json',...sessionArgs,`/skill:${skill} local read-only integration fixture`], env);
        assert(!active.error, active.error);
        assert(active.advertised, 'Skill descriptions missing from model request');
        assert(active.expanded, 'Explicit /skill command was not expanded into instructions');
        assert(active.bash, 'Built-in Bash tool was not declared');
        if (windows) {
          assert(active.powershell, 'Built-in PowerShell tool was not declared');
          const events = r.stdout.split(/\r?\n/).filter(Boolean).map(x => JSON.parse(x));
          const end = events.find(x => x.type === 'tool_execution_end' && x.toolName === 'powershell');
          assert(end && !end.isError, 'Actual PowerShell helper tool call failed');
          if (!quick) {
          const found = fs.readdirSync(reports).filter(x => x.startsWith(skill + '-') && x.endsWith('.json'));
          assert(found.length > 0, 'Helper report not produced through Pi');
          const report = JSON.parse(fs.readFileSync(path.join(reports, found[found.length-1]), 'utf8'));
          assert(report.sections.every(s => !s.required || s.status === 'ok'), 'Required Windows read-only evidence unavailable');
          }
        }
        results.push({ name: `${skill}: slash expansion and ${windows ? (quick ? 'native PowerShell fixture (diagnostics skipped)' : 'actual native PowerShell workflow') : 'Bash declaration'}`, status: 'passed' });
        if (skill === 'windows-diagnostics') {
          const sessionFiles = fs.readdirSync(path.join(temp, 'sessions'), { recursive: true }).filter(x => x.endsWith('.jsonl'));
          assert(sessionFiles.length > 0, 'PI_CODING_AGENT_SESSION_DIR did not receive the real mock-provider conversation');
          results.push({ name: 'Actual Pi session persisted in designated portable session directory (Unicode/space paths)', status: 'passed' });
        }
      } catch (e) { results.push({ name: `${skill}: integration`, status: 'failed', error: e.message }); }
    }
  } catch (e) { results.push({ name: 'Pi protocol fixture', status: 'failed', error: e.message }); }
  finally {
    server.close();
    fs.mkdirSync(path.dirname(output), { recursive: true });
    fs.writeFileSync(output, JSON.stringify({ suite: 'pi-integration', platform: process.platform, piExecutable: path.basename(pi), windowsToolExecution: windows, extendedDiagnostics: quick ? 'skipped: quick CI profile' : 'requested', automaticLlmSelection: 'not-tested: deterministic local provider', results }, null, 2));
    fs.rmSync(temp, { recursive: true, force: true });
    for (const r of results) console.log(`[${r.status}] ${r.name}${r.error ? ': ' + r.error : ''}`);
    console.log('Test results: ' + output);
    process.exitCode = results.some(x => x.status === 'failed') ? 1 : 0;
  }
})().catch(e => { server.close(); fs.rmSync(temp, { recursive: true, force: true }); console.error(e.message); process.exitCode = 1; });
