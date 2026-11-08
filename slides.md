---
theme: default
title: Multi-Tenancy in PostgreSQL
info: |
  A practical 45-minute introduction to multi-tenancy in PostgreSQL.
  Focus: schema-per-tenant, connection pooling, permissions, migrations,
  application roles, and django-tenants.
class: text-center
highlighter: shiki
lineNumbers: false
transition: slide-left
mdc: true
---

<style>
:root {
  --pg-blue: #336791;
  --ink: #172033;
  --muted: #64748b;
  --soft: #f5f7fb;
  --good: #0f766e;
  --warn: #b45309;
  --bad: #b91c1c;
}

.slidev-layout {
  color: var(--ink);
}

h1 {
  letter-spacing: -0.03em;
}

.pg-card {
  border: 1px solid #dbe3ee;
  border-radius: 18px;
  padding: 1.15rem 1.25rem;
  background: white;
  box-shadow: 0 8px 24px rgba(15, 23, 42, .05);
}

.pg-soft {
  background: var(--soft);
  border-radius: 18px;
  padding: 1.15rem 1.25rem;
}

.pg-kicker {
  text-transform: uppercase;
  letter-spacing: .14em;
  font-size: .7rem;
  font-weight: 800;
  color: var(--pg-blue);
}

.pg-big {
  font-size: 2.1rem;
  line-height: 1.18;
  font-weight: 800;
  letter-spacing: -.03em;
}

.pg-muted {
  color: var(--muted);
}

.pg-arrow {
  font-size: 2rem;
  color: var(--pg-blue);
  font-weight: 700;
}

.pg-good { color: var(--good); }
.pg-warn { color: var(--warn); }
.pg-bad  { color: var(--bad); }

code {
  font-size: .92em;
}
</style>

# Multi-Tenancy in PostgreSQL

<div class="mt-7 text-2xl font-600">
Where should the tenant boundary live?
</div>

<div class="mt-8 text-lg opacity-70">
Rows · Schemas · Databases
</div>

<div class="mt-16 text-sm opacity-55">
45-minute technical talk
</div>

<!--
TIME: 1–2 min

SCRIPT:
“Today I want to explain multi-tenancy from a PostgreSQL point of view.

The question I want us to keep asking is not simply ‘Does PostgreSQL support multi-tenancy?’
The better question is: where do we want the tenant boundary to live?

At the row level? At the schema level? Or at the database level?

I’ll spend most of the talk on schema-per-tenant, because that model gives us a very clear boundary,
but it also introduces two operational concerns that I think are especially important:
connection pooling and migrations.”
-->

---
layout: default
---

<div class="pg-kicker">Start with the problem</div>

# One application. Multiple customers.

<div class="grid grid-cols-3 gap-6 mt-10">
  <div class="pg-card text-center">
    <div class="text-4xl">🏢</div>
    <div class="font-bold text-xl mt-3">Acme</div>
    <div class="pg-muted mt-2">Tenant A</div>
  </div>

  <div class="pg-card text-center">
    <div class="text-4xl">🏭</div>
    <div class="font-bold text-xl mt-3">Stark</div>
    <div class="pg-muted mt-2">Tenant B</div>
  </div>

  <div class="pg-card text-center">
    <div class="text-4xl">🏙️</div>
    <div class="font-bold text-xl mt-3">Wayne</div>
    <div class="pg-muted mt-2">Tenant C</div>
  </div>
</div>

<div class="mt-12 pg-big text-center">
They can share infrastructure.<br>
<span class="pg-bad">They must not share data accidentally.</span>
</div>

<!--
TIME: ~2 min

SCRIPT:
“A tenant is usually a company, organization, workspace, school, hospital, customer account, etc.

The fundamental requirement is simple:
Acme must never see Stark’s private data, and Stark must never see Wayne’s data.

Everything we are going to discuss—tenant_id, RLS, schemas, permissions,
database-per-tenant—is a different way of enforcing this rule.”
-->

---

<div class="pg-kicker">Definition</div>

# What does “multi-tenant” actually mean?

<div class="grid grid-cols-2 gap-8 mt-9">
  <div class="pg-card">
    <div class="font-bold text-xl">Shared</div>
    <div class="mt-4 text-lg">
      Application code<br>
      PostgreSQL infrastructure<br>
      Deployment process<br>
      Monitoring
    </div>
  </div>

  <div class="pg-card">
    <div class="font-bold text-xl">Isolated</div>
    <div class="mt-4 text-lg">
      Customer data<br>
      Authorization boundary<br>
      Permissions<br>
      Tenant context
    </div>
  </div>
</div>

<div class="mt-11 pg-soft text-center text-xl">
Multi-tenancy is primarily an <b>isolation architecture</b>.
</div>

<!--
TIME: ~2 min

SCRIPT:
“Multi-tenancy does not necessarily mean everything is shared.
It means we deliberately choose what is shared and what is isolated.

One database server can be shared.
The application can be shared.
But customer data and authorization boundaries must be isolated.

PostgreSQL does not have one magic ‘multi-tenant mode’.
We combine normal PostgreSQL features to create the boundary we want.”
-->

---

<div class="pg-kicker">Architecture choices</div>

# Three common models

<div class="grid grid-cols-3 gap-5 mt-8">

<div class="pg-card">
  <div class="text-sm pg-muted">01</div>
  <div class="font-bold text-xl mt-2">Shared tables</div>
  <div class="font-mono mt-5">projects.tenant_id</div>
  <div class="mt-8 text-lg"><b>Boundary:</b> row</div>
</div>

<div class="pg-card">
  <div class="text-sm pg-muted">02</div>
  <div class="font-bold text-xl mt-2">Schema per tenant</div>
  <div class="font-mono mt-5">acme.projects</div>
  <div class="mt-8 text-lg"><b>Boundary:</b> schema</div>
</div>

<div class="pg-card">
  <div class="text-sm pg-muted">03</div>
  <div class="font-bold text-xl mt-2">Database per tenant</div>
  <div class="font-mono mt-5">acme_db</div>
  <div class="mt-8 text-lg"><b>Boundary:</b> database</div>
</div>

</div>

<div class="mt-10 text-center text-lg">
As the boundary moves outward, isolation becomes easier to reason about—
but operations usually get harder.
</div>

<!--
TIME: ~3 min

SCRIPT:
“This is the mental model for the whole talk.

Shared tables: all tenants share the same tables and tenant_id identifies ownership.

Schema-per-tenant: each tenant gets a namespace, like acme.projects and stark.projects.

Database-per-tenant: the tenant boundary is a complete database.

There is no universal winner.
The trade-off is usually isolation versus operational complexity.”
-->

---

<div class="pg-kicker">Model 1</div>

# Shared tables: the row owns the tenant

<div class="grid grid-cols-2 gap-8 mt-6">

<div>

```sql
CREATE TABLE projects (
  id BIGSERIAL PRIMARY KEY,
  tenant_id BIGINT NOT NULL,
  name TEXT NOT NULL
);
```

</div>

<div class="pg-card font-mono text-sm">

```text
id  tenant_id  name
--  ---------  ----------------
1   1          Acme Website
2   1          Acme API
3   2          Stark Dashboard
```

</div>

</div>

<div class="mt-8">

```sql
SELECT *
FROM projects
WHERE tenant_id = 1;
```

</div>

<div class="mt-7 pg-soft">
The row needs enough information to answer:
<b>“Who owns this data?”</b>
</div>

<!--
TIME: ~2 min

SCRIPT:
“This is probably the most common SaaS design.

Every tenant-owned row carries tenant_id.
The benefit is simplicity: one projects table, one migration, and a very efficient shared pool.

The downside is that our isolation boundary is inside the table.”
-->

---

<div class="pg-kicker">Shared-table risk</div>

# One missing filter can become a data leak

<div class="grid grid-cols-2 gap-8 mt-10">

<div class="pg-card">
  <div class="font-bold pg-good">Expected</div>

```sql
SELECT *
FROM projects
WHERE tenant_id = 1;
```

</div>

<div class="pg-card">
  <div class="font-bold pg-bad">Bug</div>

```sql
SELECT *
FROM projects;
```

</div>

</div>

<div class="mt-10 text-center text-xl">
This is why shared-table designs often use
<b>defense in depth</b>.
</div>

<div class="mt-7 text-center">
Application scoping → RLS → constraints → permissions
</div>

<!--
TIME: ~2 min

SCRIPT:
“This is the biggest conceptual risk.

If our entire isolation model depends on every developer remembering a WHERE tenant_id clause,
one bug can expose another customer’s data.

So we normally add another layer at the database level.”
-->

---

<div class="pg-kicker">PostgreSQL protection</div>

# Row Level Security (RLS)

```sql
ALTER TABLE projects
ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_policy
ON projects
USING (
  tenant_id =
  current_setting('app.current_tenant')::BIGINT
);
```

<div class="grid grid-cols-3 gap-5 mt-8">
  <div class="pg-card text-center">
    <div class="font-bold">App</div>
    <div class="mt-2">sets tenant context</div>
  </div>
  <div class="pg-arrow text-center self-center">→</div>
  <div class="pg-card text-center">
    <div class="font-bold">PostgreSQL</div>
    <div class="mt-2">filters allowed rows</div>
  </div>
</div>

<div class="mt-8 text-center text-lg">
The database can enforce the boundary even when the query itself is incomplete.
</div>

<!--
TIME: ~3 min

SCRIPT:
“RLS is one of PostgreSQL’s strongest tools for shared-table tenancy.

The application establishes the current tenant, and PostgreSQL applies a policy.
That means SELECT * FROM projects can still return only the current tenant’s rows.

Important: your application role should not be a superuser or a role that can bypass RLS.”
-->

---

<div class="pg-kicker">Model 2 — focus of this talk</div>

# Schema per tenant

<div class="mt-8 flex items-stretch justify-center gap-5">

<div class="pg-card text-center w-48 flex flex-col justify-center">
  <div class="text-sm pg-muted">Shared instance</div>
  <div class="font-bold text-2xl mt-2">PostgreSQL</div>
</div>

<div class="pg-arrow self-center">→</div>

<div class="pg-card flex-1">
  <div class="text-sm pg-muted">One database · app</div>

  <div class="grid grid-cols-3 gap-4 mt-5">
    <div class="pg-soft">
      <div class="font-bold text-lg">public</div>
      <div class="font-mono text-sm mt-3">tenants<br>domains</div>
      <div class="pg-muted text-sm mt-3">shared metadata</div>
    </div>
    <div class="pg-soft">
      <div class="font-bold text-lg">acme</div>
      <div class="font-mono text-sm mt-3">projects<br>tasks</div>
      <div class="pg-muted text-sm mt-3">tenant schema</div>
    </div>
    <div class="pg-soft">
      <div class="font-bold text-lg">stark</div>
      <div class="font-mono text-sm mt-3">projects<br>tasks</div>
      <div class="pg-muted text-sm mt-3">tenant schema</div>
    </div>
  </div>
</div>

</div>

<div class="mt-8 text-center text-xl">
The database stays shared. Each tenant gets its own schema.
</div>

<!--
TIME: ~3 min

SCRIPT:
“Now we move the boundary from the row to the schema.

Instead of Acme and Stark sharing public.projects,
we have acme.projects and stark.projects.

The database is still shared, and the PostgreSQL instance can still be shared,
but each tenant gets a separate namespace.

This is the architecture I want to focus on from here.”
-->

---

<div class="pg-kicker">Schema anatomy</div>

# The schema becomes the tenant boundary

<div class="grid grid-cols-3 gap-6 mt-8">

<div class="pg-card">
  <div class="font-bold text-xl">public</div>
  <div class="mt-4 font-mono text-sm">
    tenants<br>
    domains<br>
    plans
  </div>
  <div class="pg-muted mt-5">shared metadata</div>
</div>

<div class="pg-card">
  <div class="font-bold text-xl">acme</div>
  <div class="mt-4 font-mono text-sm">
    projects<br>
    tasks<br>
    users
  </div>
  <div class="pg-muted mt-5">tenant-owned data</div>
</div>

<div class="pg-card">
  <div class="font-bold text-xl">stark</div>
  <div class="mt-4 font-mono text-sm">
    projects<br>
    tasks<br>
    users
  </div>
  <div class="pg-muted mt-5">tenant-owned data</div>
</div>

</div>

<div class="mt-10 text-center text-xl">
In this model, <code>tenant_id</code> is often unnecessary
inside tenant-owned tables.
</div>

<!--
TIME: ~2 min

SCRIPT:
“This answers an important question we discussed earlier:
why would I need tenant_id if the schema itself represents the tenant?

Often, you don’t.

Inside acme.projects, every row already belongs to Acme by construction.
That also means a normal project_id foreign key can often be enough inside the same schema.”
-->

---

<div class="pg-kicker">Routing</div>

# `search_path` tells PostgreSQL where to look

<div class="grid grid-cols-2 gap-8 mt-7">

<div class="pg-card">

```sql
SET search_path
TO acme, public;

SELECT *
FROM projects;
```

</div>

<div class="pg-card">

PostgreSQL resolves:

```text
projects
   ↓
acme.projects
```

If not found:

```text
public.projects
```

</div>

</div>

<div class="mt-9 pg-soft text-center text-lg">
<b>Important:</b> <code>search_path</code> is primarily routing.
It is not automatically a security boundary.
</div>

<!--
TIME: ~3 min

SCRIPT:
“search_path is what makes schema-per-tenant attractive for ORMs.

Our Django model can still say Project.objects.all().
We do not necessarily rewrite every query to include acme.projects.

But this distinction is critical:
search_path tells PostgreSQL which schema to resolve first.
It does not automatically mean the current database role is forbidden from querying stark.projects explicitly.”
-->

---

<div class="pg-kicker">Enforcement</div>

# Schemas can have permissions

<div class="grid grid-cols-2 gap-8 mt-6">

<div>

```sql
GRANT USAGE
ON SCHEMA acme
TO acme_role;

GRANT SELECT, INSERT,
UPDATE, DELETE
ON ALL TABLES
IN SCHEMA acme
TO acme_role;
```

</div>

<div class="pg-card">
  <div class="font-bold text-lg">Two separate ideas</div>

  <div class="mt-6">
    <b>search_path</b><br>
    <span class="pg-muted">Where should PostgreSQL look?</span>
  </div>

  <div class="mt-6">
    <b>GRANT / REVOKE</b><br>
    <span class="pg-muted">What is this role actually allowed to access?</span>
  </div>
</div>

</div>

<!--
TIME: ~3 min

SCRIPT:
“This is the difference between routing and enforcement.

We can grant USAGE on a schema and CRUD privileges on its tables.
We can also revoke access to other schemas.

So schemas can become a real permission boundary—but the more tenant-specific roles we create,
the more complicated credentials and pooling become.”
-->

---

<div class="pg-kicker">Application roles</div>

# One DB user per tenant… or one superuser?

<div class="grid grid-cols-3 gap-5 mt-7">

<div class="pg-card">
  <div class="font-bold pg-good">Restricted shared runtime role</div>
  <div class="mt-4 text-sm">
    Simple pooling<br>
    Fewer credentials<br>
    Least privilege possible
  </div>
  <div class="mt-5 font-bold">Usually my default</div>
</div>

<div class="pg-card">
  <div class="font-bold">Role / tenant</div>
  <div class="mt-4 text-sm">
    Stronger DB-level isolation<br>
    More secrets<br>
    Harder pool management
  </div>
  <div class="mt-5 font-bold">Use when justified</div>
</div>

<div class="pg-card">
  <div class="font-bold pg-bad">Superuser</div>
  <div class="mt-4 text-sm">
    Broad privileges<br>
    Huge blast radius<br>
    Weak least-privilege story
  </div>
  <div class="mt-5 font-bold">Avoid for web traffic</div>
</div>

</div>

<!--
TIME: ~3 min

SCRIPT:
“My preference at the application level is usually one restricted runtime role,
not one PostgreSQL login per application user or tenant.

Then use a separate migration/provisioning role with DDL privileges.

A superuser is convenient, but convenience is exactly the problem:
a bug in a superuser-backed web app has an unnecessarily large blast radius.”
-->

---

<div class="pg-kicker">Concern #1</div>

# Connection pooling

<div class="mt-8 flex items-center justify-center gap-6">

<div class="pg-card text-center">
  <div class="font-bold">Tenants</div>
  <div class="mt-3">A · B · C · D</div>
</div>

<div class="pg-arrow">→</div>

<div class="pg-card text-center">
  <div class="font-bold">Web app</div>
  <div class="mt-3">tenant resolver</div>
</div>

<div class="pg-arrow">→</div>

<div class="pg-card text-center">
  <div class="font-bold">Pool</div>
  <div class="mt-3 font-mono">C1 C2 C3 C4</div>
</div>

<div class="pg-arrow">→</div>

<div class="pg-card text-center">
  <div class="font-bold">PostgreSQL</div>
  <div class="mt-3">one database</div>
</div>

</div>

<div class="mt-12 pg-big text-center">
A connection should not permanently belong to a tenant.
</div>

<!--
TIME: ~3 min

SCRIPT:
“This was one of my biggest concerns initially.

The important realization is: schema-per-tenant does not mean one pool per tenant.

Tenants can share the same pool because all schemas live in the same database.

A physical connection can serve Acme now and Stark later.
That makes the state on that connection very important.”
-->

---

<div class="pg-kicker">Pooling risk</div>

# Tenant state can leak through a reused connection

<div class="grid grid-cols-2 gap-8 mt-7">

<div class="pg-card">

<div class="font-bold pg-bad">Risky</div>

```sql
SET search_path TO acme;

-- request finishes
-- connection returns to pool
```

<div class="mt-3">
What state does the next request inherit?
</div>

</div>

<div class="pg-card">

<div class="font-bold pg-good">Generic transaction-scoped idea</div>

```sql
BEGIN;

SET LOCAL search_path
TO acme, public;

-- queries

COMMIT;
```

</div>

</div>

<div class="mt-9 text-center text-xl">
<b>Connections belong to the pool.<br>
Tenant context belongs to the request or transaction.</b>
</div>

<!--
TIME: ~4 min

SCRIPT:
“This is the danger.

If we store tenant-specific state on a session and do not reset it correctly,
the next request can inherit the previous tenant’s search_path.

A generic safe design is to scope tenant state to a transaction when possible.

The exact implementation depends on the framework and pooler.
The principle is what matters: tenant-specific connection state must never leak between requests.”
-->

---

<div class="pg-kicker">External poolers</div>

# PgBouncer: session vs transaction pooling

<div class="grid grid-cols-2 gap-8 mt-8">

<div class="pg-card">
  <div class="font-bold text-xl">Session pooling</div>
  <div class="mt-5">
    Client session keeps the same server connection longer.
  </div>
  <div class="mt-5 pg-muted">
    Session state is easier to reason about.
  </div>
</div>

<div class="pg-card">
  <div class="font-bold text-xl">Transaction pooling</div>
  <div class="mt-5">
    Server connection can change after every transaction.
  </div>
  <div class="mt-5 pg-muted">
    Better multiplexing, but session state cannot be assumed to persist.
  </div>
</div>

</div>

<div class="mt-9 pg-soft text-center">
If your tenancy library depends on session-level schema state,
<b>pool mode becomes an architectural compatibility question.</b>
</div>

<!--
TIME: ~3 min

SCRIPT:
“I don’t want this to become a PgBouncer talk.

The one thing to remember is that session pooling preserves a client/server relationship longer,
while transaction pooling aggressively reuses server connections.

If our tenant routing depends on session-level search_path,
we need to understand exactly what our framework or library expects before enabling transaction pooling.”
-->

---

<div class="pg-kicker">Concern #2</div>

# Migrations become a fan-out problem

<div class="grid grid-cols-2 gap-10 mt-8">

<div>
<div class="font-bold text-xl mb-5">Shared table</div>

```text
public.projects
      │
      ▼
  migration
      │
      ▼
     done
```
</div>

<div>
<div class="font-bold text-xl mb-5">Schema per tenant</div>

```text
acme.projects   → migrate
stark.projects  → migrate
wayne.projects  → migrate
tenant_004      → migrate
tenant_005      → migrate
...
```
</div>

</div>

<div class="mt-10 text-center text-xl">
One logical migration becomes <b>N physical migrations</b>.
</div>

<!--
TIME: ~3 min

SCRIPT:
“This, to me, is the bigger operational cost of schema-per-tenant.

With shared tables, ALTER TABLE projects runs once.

With one schema per tenant, the same logical migration has to be applied repeatedly.
At 10 tenants this is simple.
At 1,000 or 10,000 tenants, migration orchestration becomes a first-class system.”
-->

---

<div class="pg-kicker">Failure scenario</div>

# What if Tenant C fails?

<div class="mt-8 font-mono text-xl leading-10">

```text
Tenant A  → v15  ✅ committed
Tenant B  → v15  ✅ committed
Tenant C  → v14  ❌ migration failed
Tenant D  → v14  ⏳ pending
Tenant E  → v14  ⏳ pending
```

</div>

<div class="mt-10 pg-soft">
If A and B already committed, they normally <b>stay migrated</b>.

Tenant C can roll back <b>its own</b> migration.

Now production temporarily contains <b>multiple schema versions</b>.
</div>

<!--
TIME: ~4 min

SCRIPT:
“This is the scenario I would expect someone to ask in a design review.

If each tenant migration is its own transaction, A and B are already committed.
C fails and rolls back.
D and E may not have run yet.

That means our application has to survive a temporary mixed-version world—or we stop the rollout
before deploying code that requires v15 everywhere.”
-->

---

<div class="pg-kicker">Recovery strategy</div>

# Make tenant migrations observable and resumable

<div class="grid grid-cols-3 gap-5 mt-8">

<div class="pg-card">
  <div class="font-bold">1. Track</div>
  <div class="mt-4 font-mono text-sm">
    acme → v15<br>
    stark → v15<br>
    wayne → v14
  </div>
</div>

<div class="pg-card">
  <div class="font-bold">2. Retry</div>
  <div class="mt-4 text-sm">
    Skip completed tenants.<br>
    Retry only failed/pending tenants.
  </div>
</div>

<div class="pg-card">
  <div class="font-bold">3. Report</div>
  <div class="mt-4 text-sm">
    Know exactly which tenant failed and why.
  </div>
</div>

</div>

<div class="mt-10 text-center text-xl">
A migration runner should be <b>restartable</b>, not “all or nothing forever.”
</div>

<!--
TIME: ~3 min

SCRIPT:
“The operational answer is per-tenant migration state.

We need to know which tenants completed, which failed, and which are pending.

On retry, completed tenants are skipped and only missing work is performed.

You also have to choose a policy:
stop at the first failure to minimize version divergence,
or continue and report failures so one bad tenant does not block everybody.”
-->

---

<div class="pg-kicker">Deployment safety</div>

# Expand → migrate → switch → contract

<div class="mt-12 flex items-center justify-center gap-4 text-center">

<div class="pg-card w-44">
  <div class="font-bold">Expand</div>
  <div class="text-sm mt-3">Add new structure</div>
</div>

<div class="pg-arrow">→</div>

<div class="pg-card w-44">
  <div class="font-bold">Migrate</div>
  <div class="text-sm mt-3">All tenant schemas</div>
</div>

<div class="pg-arrow">→</div>

<div class="pg-card w-44">
  <div class="font-bold">Switch</div>
  <div class="text-sm mt-3">App uses new shape</div>
</div>

<div class="pg-arrow">→</div>

<div class="pg-card w-44">
  <div class="font-bold">Contract</div>
  <div class="text-sm mt-3">Remove old structure</div>
</div>

</div>

<div class="mt-12 pg-soft text-center text-lg">
Avoid deploying application code that immediately requires a migration
that may still be missing on some tenants.
</div>

<!--
TIME: ~3 min

SCRIPT:
“Expand/contract is a very good fit for multi-schema deployments.

First add a backwards-compatible column or table.
Then migrate all tenants.
Only after the fleet is ready do we switch application behavior.
Old structure is removed later.

This reduces the impact of partial tenant migration failures.”
-->

---

<div class="pg-kicker">Schema drift</div>

# What if Acme needs a custom column?

<div class="grid grid-cols-2 gap-8 mt-6">

<div>

```sql
ALTER TABLE acme.projects
ADD COLUMN cost_center TEXT;
```

<div class="mt-5 font-mono text-sm">
Acme  → projects + cost_center<br>
Stark → standard projects<br>
Wayne → standard projects
</div>

</div>

<div class="pg-card">
  <div class="font-bold pg-warn text-xl">Technically easy.</div>
  <div class="mt-4 text-lg">Operationally expensive.</div>

  <div class="mt-5 text-sm">
    Migrations diverge<br>
    ORM assumptions diverge<br>
    Testing grows<br>
    Tenant versions become harder to reason about
  </div>
</div>

</div>

<div class="mt-8 text-center">
Prefer <b>JSONB</b> or a <b>custom-fields table</b>
when customization is data, not a truly different product.
</div>

<!--
TIME: ~3 min

SCRIPT:
“Schema-per-tenant gives us a temptation: ‘It’s easy, just add the column to Acme.’

But every one-off DDL change creates schema drift.

I would keep tenant schemas identical whenever possible and represent customer-specific fields as data,
for example JSONB or a custom field model.”
-->

---

<div class="pg-kicker">Django</div>

# How `django-tenants` fits the model

<div class="mt-8 flex items-center justify-center gap-4 text-center">

<div class="pg-card w-42">
  <div class="font-bold">Request</div>
  <div class="text-sm mt-3">acme.example.com</div>
</div>

<div class="pg-arrow">→</div>

<div class="pg-card w-46">
  <div class="font-bold">Middleware</div>
  <div class="text-sm mt-3">resolve domain → tenant</div>
</div>

<div class="pg-arrow">→</div>

<div class="pg-card w-46">
  <div class="font-bold">Schema context</div>
  <div class="text-sm mt-3">acme + public</div>
</div>

<div class="pg-arrow">→</div>

<div class="pg-card w-42">
  <div class="font-bold">ORM</div>
  <div class="text-sm mt-3">Project.objects.all()</div>
</div>

</div>

<div class="mt-10 pg-soft">
The library separates apps into concepts such as
<b>shared apps</b> and <b>tenant apps</b>,
and provides schema-aware migration commands.
</div>

<!--
TIME: ~4 min

SCRIPT:
“django-tenants is basically an implementation of the architecture we have been discussing.

A request comes in with a domain.
Middleware resolves the domain to a tenant.
The active PostgreSQL schema context is adjusted.
Normal ORM code can then operate against the current tenant schema.

It also distinguishes shared applications from tenant applications
and provides migrate_schemas to apply the correct migrations to public and tenant schemas.

The key point is that the library makes schema selection transparent,
but it does not remove the operational concerns we discussed.
You still need to understand pooling and migration behavior.”
-->

---

<div class="pg-kicker">Recommended application design</div>

# Separate runtime privileges from migration privileges

<div class="mt-9 flex items-start justify-center gap-16">

<div class="pg-card w-74">
  <div class="font-bold text-xl">app_runtime</div>
  <div class="mt-5">
    SELECT<br>
    INSERT<br>
    UPDATE<br>
    DELETE
  </div>
  <div class="mt-6 pg-good font-bold">Web requests</div>
</div>

<div class="pg-card w-74">
  <div class="font-bold text-xl">app_migrator</div>
  <div class="mt-5">
    CREATE SCHEMA<br>
    CREATE / ALTER TABLE<br>
    migration operations
  </div>
  <div class="mt-6 pg-warn font-bold">Deploy / provisioning only</div>
</div>

</div>

<div class="mt-10 text-center text-xl">
Least privilege keeps normal application traffic away from DDL power.
</div>

<!--
TIME: ~3 min

SCRIPT:
“This is the database-role shape I would start with.

The normal web application gets a restricted runtime role.

Provisioning and migrations use a separate role with enough DDL privileges.

This also means tenant creation can be an explicit provisioning workflow:
create tenant metadata, create schema, migrate it, and only then mark the tenant ready.”
-->

---

<div class="pg-kicker">Decision matrix</div>

# Advantages and trade-offs

| | Shared tables | Schema / tenant | DB / tenant |
|---|---:|---:|---:|
| Tenant boundary | Row | Schema | Database |
| Pool efficiency | Excellent | Good | Harder |
| Migration simplicity | Excellent | Medium / hard | Hard |
| Structural isolation | Low | Strong | Strongest |
| RLS usefulness | High | Optional / contextual | Usually low |
| Per-tenant customization | Harder | Easy* | Easy |
| Operational cost | Lowest | Medium | Highest |

<div class="mt-5 text-sm opacity-60">
*Easy technically; potentially expensive due to schema drift.
</div>

<!--
TIME: ~4 min

SCRIPT:
“This is the slide I would use to answer ‘Which model is best?’

Shared tables optimize operations.
Schema-per-tenant gives us a very visible logical boundary but makes migrations and connection state more important.
Database-per-tenant gives the strongest structural boundary but increases routing, connection, backup, and provisioning complexity.

The best model depends on your requirements.”
-->

---

<div class="pg-kicker">When I would consider schema-per-tenant</div>

# Schema-per-tenant is attractive when…

<div class="grid grid-cols-2 gap-7 mt-8">

<div class="pg-card">
  <div class="font-bold pg-good">Good fit</div>
  <div class="mt-5">
    Clear tenant namespace matters<br><br>
    Per-schema permissions are useful<br><br>
    Tenant count is operationally manageable<br><br>
    You can invest in migration orchestration
  </div>
</div>

<div class="pg-card">
  <div class="font-bold pg-warn">Be careful when</div>
  <div class="mt-5">
    Tenant count may become massive<br><br>
    Schema drift is common<br><br>
    Migrations are frequent/heavy<br><br>
    Pooling requirements conflict with session state
  </div>
</div>

</div>

<!--
TIME: ~3 min

SCRIPT:
“I would not choose schema-per-tenant just because it sounds safer.

I would choose it when the structural separation gives us real value and
we are prepared to own the migration and connection lifecycle.

If we expect enormous tenant counts and identical data models,
shared tables plus strong RLS may actually be operationally cleaner.”
-->

---

<div class="pg-kicker">Design checklist</div>

# Questions I would ask before committing

<div class="grid grid-cols-2 gap-x-10 gap-y-5 mt-8 text-lg">

<div>✓ How is the tenant resolved?</div>
<div>✓ What is shared vs tenant-owned?</div>

<div>✓ How is schema state set/reset?</div>
<div>✓ Which connection pool mode is used?</div>

<div>✓ What DB role serves web traffic?</div>
<div>✓ Who is allowed to run DDL?</div>

<div>✓ How are migrations tracked per tenant?</div>
<div>✓ What happens after a partial failure?</div>

<div>✓ Can app versions tolerate mixed schemas?</div>
<div>✓ How do we prevent schema drift?</div>

</div>

<!--
TIME: ~2 min

SCRIPT:
“This is the checklist I would take into an architecture review.

A design is not complete when we say ‘one schema per tenant’.
We need answers for request routing, permissions, pooling, migrations,
failure recovery, and schema consistency.”
-->

---
layout: center
class: text-center
---

<div class="pg-kicker">Takeaway</div>

# Multi-tenancy is a boundary

<div class="mt-8 text-2xl leading-relaxed max-w-4xl mx-auto">
PostgreSQL lets us place that boundary at the
<b>row</b>, <b>schema</b>, or <b>database</b> level.
</div>

<div class="mt-12 grid grid-cols-2 gap-8 max-w-3xl mx-auto">
  <div class="pg-card">
    <div class="text-3xl">🔌</div>
    <div class="font-bold text-xl mt-3">Connection state</div>
    <div class="mt-2 pg-muted">must never leak tenants</div>
  </div>
  <div class="pg-card">
    <div class="text-3xl">🧱</div>
    <div class="font-bold text-xl mt-3">Migrations</div>
    <div class="mt-2 pg-muted">must be observable and resumable</div>
  </div>
</div>

<div class="mt-12 text-xl">
For schema-per-tenant, these are the two operational areas I would design first.
</div>

<!--
TIME: ~2 min

SCRIPT:
“My main takeaway is that multi-tenancy is a boundary problem.

PostgreSQL gives us several places to enforce the boundary.
Schema-per-tenant gives us a clean, understandable structure,
but it moves complexity into operations.

If I were reviewing this architecture, the first two things I would want confidence in
are connection-state safety and migration orchestration.”
-->

---
layout: center
class: text-center
---

# Questions?

<div class="mt-8 text-xl opacity-70">
Row isolation · schema isolation · pooling · migrations · django-tenants
</div>

<!--
Optional Q&A buffer: 3–5 min
-->

---

<div class="pg-kicker">Appendix</div>

# Useful SQL to demo live

```sql
CREATE SCHEMA acme;
CREATE SCHEMA stark;

CREATE TABLE acme.projects (
  id BIGSERIAL PRIMARY KEY,
  name TEXT NOT NULL
);

CREATE TABLE stark.projects (
  id BIGSERIAL PRIMARY KEY,
  name TEXT NOT NULL
);

INSERT INTO acme.projects (name)
VALUES ('Acme Website');

INSERT INTO stark.projects (name)
VALUES ('Stark Dashboard');

SET search_path TO acme, public;
SELECT * FROM projects;

SET search_path TO stark, public;
SELECT * FROM projects;
```

<!--
Use this only if you want a live demo or somebody asks how search_path works.
-->

---

<div class="pg-kicker">Appendix</div>

# Useful questions you may get

<div class="text-left max-w-4xl mx-auto mt-7 leading-9">

**Why not just use one database per tenant?**  
Stronger isolation, but more connection routing, provisioning and migration overhead.

**Why not one PostgreSQL role per tenant?**  
Possible, but credentials and pooling become more complex.

**Can one tenant have custom tables/columns?**  
Yes, but avoid uncontrolled schema drift.

**What if one migration fails?**  
Already-committed tenants remain migrated; track, retry and design for temporary version divergence.

**Does `search_path` equal security?**  
No. It controls name resolution; permissions are a separate concern.

</div>

---

<div class="pg-kicker">References</div>

# Further reading

<div class="text-left max-w-4xl mx-auto mt-8 leading-9">

- PostgreSQL Documentation — **Schemas**
- PostgreSQL Documentation — **Row Security Policies**
- PostgreSQL Documentation — **GRANT / Role Privileges**
- django-tenants Documentation — **Installation**
- django-tenants Documentation — **Using django-tenants / migrate_schemas**

</div>

<div class="mt-10 text-sm opacity-60">
Keep this slide as an appendix rather than spending talk time on it.
</div>