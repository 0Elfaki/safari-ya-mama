// admin-users: staff and admin accounts for the Safari ya Mama dashboard.
//
// The service_role key exists only here. Every request carries the caller's JWT (verify_jwt on),
// and every permission is decided in Postgres with the CALLER's JWT:
//   can_manage_account(role, facility)  may the caller create this kind of account here?
//   can_manage_user(target)             may the caller deactivate / reset / re-invite this account?
// so the rules are the same ones the SQL tests prove (supabase/tests/permissions.sql).
//
// Actions (POST JSON {action, ...}):
//   create            {email, display_name, role, facility_id?, method: 'invite' | 'temp_password'}
//   resend_invite     {user_id}
//   reset_password    {user_id, method: 'email' | 'temp_password'}
//   deactivate        {user_id}          (ban, never delete)
//   reactivate        {user_id}
//   create_facility   {name, level, district_id, phone?, emergency_24h?, lat?, lng?}  (forwarded to admin_save_facility)
// A temporary password is returned once in the response and never stored or logged.
// Every action writes audit_log (actor, action, target id; no email, no password).
import { createClient } from 'npm:@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const DASHBOARD_URL = Deno.env.get('DASHBOARD_URL') ?? '';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });

// Website team roles (editor, author, clinical_reviewer, viewer) sign in under Administration and see
// only the Website section; can_manage_account() decides who may create them (platform admins).
const ROLES = ['health_worker', 'facility_admin', 'programme_admin', 'super_admin', 'editor', 'author', 'clinical_reviewer', 'viewer'] as const;
const FACILITY_ROLES = ['health_worker', 'facility_admin'];
const EMAIL = /^[^\s@]{1,64}@[^\s@]{1,190}\.[A-Za-z]{2,24}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// 16 characters, at least one of each class, no look-alikes (0/O, 1/l/I).
function tempPassword(): string {
  const sets = ['ABCDEFGHJKLMNPQRSTUVWXYZ', 'abcdefghijkmnpqrstuvwxyz', '23456789', '!#$%*+-=?@'];
  const all = sets.join('');
  const pick = (s: string) => s[crypto.getRandomValues(new Uint32Array(1))[0] % s.length];
  const chars = [...sets.map(pick), ...Array.from({ length: 12 }, () => pick(all))];
  for (let i = chars.length - 1; i > 0; i--) {
    const j = crypto.getRandomValues(new Uint32Array(1))[0] % (i + 1);
    [chars[i], chars[j]] = [chars[j], chars[i]];
  }
  return chars.join('');
}

class Refused extends Error {
  constructor(public status: number, message: string) { super(message); }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });
  if (req.method !== 'POST') return json(405, { error: 'POST only' });

  const authorization = req.headers.get('Authorization') ?? '';
  const caller = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const service = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });

  const { data: who } = await caller.auth.getUser();
  if (!who?.user) return json(401, { error: 'Sign in again.' });
  const actor = who.user.id;
  const redirectTo = DASHBOARD_URL || req.headers.get('origin') || undefined;

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: 'Send JSON.' });
  }
  const str = (k: string) => (typeof body[k] === 'string' ? (body[k] as string).trim() : '');

  const audit = (action: string, details: Record<string, unknown>) =>
    service.from('audit_log').insert({ actor_id: actor, action, details });
  const mayCreate = async (role: string, facility: string | null) => {
    const { data, error } = await caller.rpc('can_manage_account', { p_role: role, p_facility: facility });
    if (error || data !== true) throw new Refused(403, 'You are not allowed to create this account.');
  };
  const mayManage = async (target: string) => {
    if (!UUID.test(target)) throw new Refused(400, 'Unknown account.');
    const { data, error } = await caller.rpc('can_manage_user', { p_target: target });
    if (error || data !== true) throw new Refused(403, 'You are not allowed to change this account.');
  };
  const emailOf = async (id: string) => {
    const { data, error } = await service.auth.admin.getUserById(id);
    if (error || !data.user?.email) throw new Refused(404, 'Account not found.');
    return data.user;
  };

  try {
    switch (str('action')) {
      case 'create': {
        const email = str('email').toLowerCase(), name = str('display_name'), role = str('role');
        const facility = str('facility_id') || null, method = str('method') || 'invite';
        if (!EMAIL.test(email)) throw new Refused(400, 'Enter a valid email address.');
        if (name.length < 2 || name.length > 80) throw new Refused(400, 'Enter the person’s name (2 to 80 letters).');
        if (!ROLES.includes(role as typeof ROLES[number])) throw new Refused(400, 'Choose a role.');
        if (FACILITY_ROLES.includes(role) && (!facility || !UUID.test(facility))) throw new Refused(400, 'Choose the facility.');
        if (!['invite', 'temp_password'].includes(method)) throw new Refused(400, 'Choose invite or temporary password.');
        await mayCreate(role, FACILITY_ROLES.includes(role) ? facility : null);

        let id: string, password: string | undefined;
        if (method === 'invite') {
          // the invite link signs them in once; the dashboard then makes them choose a password
          const { data, error } = await service.auth.admin.inviteUserByEmail(email, { data: { display_name: name, must_change_password: true }, redirectTo });
          if (error) throw new Refused(/already/i.test(error.message) ? 409 : 400,
            /already/i.test(error.message) ? 'An account with this email already exists.' : 'The invite could not be sent.');
          id = data.user.id;
        } else {
          password = tempPassword();
          const { data, error } = await service.auth.admin.createUser({
            email, password, email_confirm: true, user_metadata: { display_name: name, must_change_password: true },
          });
          if (error) throw new Refused(/already/i.test(error.message) ? 409 : 400,
            /already/i.test(error.message) ? 'An account with this email already exists.' : 'The account could not be created.');
          id = data.user.id;
        }
        // the sign-up trigger made a 'mother' profile: turn it into the staff profile
        const p = await service.from('profiles').update({ role, display_name: name }).eq('id', id);
        if (p.error) throw new Refused(500, 'The account was created but its role could not be set. Try again from People.');
        if (FACILITY_ROLES.includes(role) && facility) {
          const a = await service.from('staff_assignments')
            .upsert({ staff_id: id, facility_id: facility, active: true, assigned_by: actor }, { onConflict: 'staff_id,facility_id' });
          if (a.error) throw new Refused(500, 'The account was created but not assigned to the facility. Assign it from People.');
        }
        await audit('account_create', { target: id, role, facility_id: facility, method });
        return json(200, { ok: true, user_id: id, ...(password ? { temp_password: password } : {}) });
      }

      case 'resend_invite': {
        const target = str('user_id');
        await mayManage(target);
        const u = await emailOf(target);
        const { error } = u.email_confirmed_at
          ? await service.auth.resetPasswordForEmail(u.email!, { redirectTo })
          : await service.auth.admin.inviteUserByEmail(u.email!, { redirectTo });
        if (error) throw new Refused(400, 'The email could not be sent. Try again in a minute.');
        await audit('account_resend_invite', { target });
        return json(200, { ok: true });
      }

      case 'reset_password': {
        const target = str('user_id'), method = str('method') || 'email';
        await mayManage(target);
        const u = await emailOf(target);
        if (method === 'temp_password') {
          const password = tempPassword();
          const { error } = await service.auth.admin.updateUserById(target, {
            password, user_metadata: { ...(u.user_metadata ?? {}), must_change_password: true },
          });
          if (error) throw new Refused(400, 'The password could not be reset.');
          await audit('account_reset_password', { target, method });
          return json(200, { ok: true, temp_password: password });
        }
        const { error } = await service.auth.resetPasswordForEmail(u.email!, { redirectTo });
        if (error) throw new Refused(400, 'The reset email could not be sent. Try again in a minute.');
        await audit('account_reset_password', { target, method: 'email' });
        return json(200, { ok: true });
      }

      case 'deactivate':
      case 'reactivate': {
        const target = str('user_id'), off = str('action') === 'deactivate';
        await mayManage(target);
        const { error } = await service.auth.admin.updateUserById(target, { ban_duration: off ? '876000h' : 'none' });
        if (error) throw new Refused(400, 'The account could not be changed.');
        await audit(off ? 'account_deactivate' : 'account_reactivate', { target });
        return json(200, { ok: true });
      }

      case 'create_facility': {
        const num = (k: string) => (body[k] === null || body[k] === undefined || body[k] === '' ? null : Number(body[k]));
        // permission and validation are in Postgres (super admin only)
        const { data, error } = await caller.rpc('admin_save_facility', {
          p_id: null, p_name: str('name'), p_level: str('level'), p_district: str('district_id') || null,
          p_phone: str('phone') || null, p_emergency_24h: body.emergency_24h === true, p_lat: num('lat'), p_lng: num('lng'),
        });
        if (error) throw new Refused(error.code === '42501' ? 403 : 400, error.message);
        return json(200, { ok: true, facility_id: data });
      }

      default:
        return json(400, { error: 'Unknown action.' });
    }
  } catch (e) {
    if (e instanceof Refused) return json(e.status, { error: e.message });
    console.error('admin-users failed', (e as Error).name); // never the body: it can hold emails
    return json(500, { error: 'Something went wrong. Try again.' });
  }
});
