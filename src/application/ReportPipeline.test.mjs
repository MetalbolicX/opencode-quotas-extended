// ReportPipeline integration test via Node.js
// Tests the compiled ReportPipeline.res.mjs directly

import { reportQuotas } from '../../lib/es6/src/application/ReportPipeline.res.mjs';
import * as Domain from '../../lib/es6/src/domain/Domain.res.mjs';

// Helper to create quota data matching Domain quotaData type
// Note: limit/used are raw floats (not wrapped in Some), reset/info/modelId are null for None
const makeQuotaData = (overrides = {}) => ({
  id: 'test-provider',
  providerName: 'TestProvider',
  used: 50.0,
  limit: 100.0,
  unit: 'requests',
  reset: null,
  window: 'daily',
  info: null,
  modelId: null,
  ...overrides,
});

// Create a noop history store
const makeNoopHistory = () => ({
  append: async (id, pt) => {},
  getHistory: async (id, ms) => [],
  prune: async (ms) => {},
  resetDetected: (id, pt, prev, curr) => false,
});

// Create test deps
const makeTestDeps = (providers = []) => ({
  credentialResolver: { get: async (id) => null },
  httpClient: { request: async (url, opts) => {} },
  registry: {
    list: () => providers,
    get: (id) => providers.find(p => p.id === id),
  },
  historyStore: makeNoopHistory(),
  config: {
    displayMode: 'table',
    disabled: [],
    aggregatedGroups: {},
    historyMaxAgeHours: 24.0,
    predictionWindowMinutes: 60.0,
    predictionShortWindowMinutes: 5.0,
    showUnaggregated: true,
    progressBar: null,
  },
  logger: {
    debug: () => {},
    info: () => {},
    warn: () => {},
    error: () => {},
  },
});

const makeTestOpts = (overrides = {}) => ({
  providerId: undefined,
  modelId: undefined,
  mode: 'table',
  compact: undefined,
  color: undefined,
  now: undefined,
  ...overrides,
});

let passed = 0;
let failed = 0;

async function runTests() {
  // Test 1: Empty providers
  {
    const deps = makeTestDeps([]);
    const opts = makeTestOpts();
    const result = await reportQuotas(deps, opts);
    if (result.errors['_'] === 'No providers found.' && result.rendered === '') {
      console.log('PASS: empty providers');
      passed++;
    } else {
      console.log('FAIL: empty providers', result);
      failed++;
    }
  }

  // Test 2: Single provider success
  {
    const q1 = makeQuotaData({ id: 'provider1', providerName: 'TestProvider', used: 50.0, limit: 100.0 });
    const provider = {
      id: 'provider1',
      displayName: 'Test Provider',
      category: 'test',
      authStrategy: 'api',
      isAvailable: async () => true,
      fetchQuotas: async () => [q1],
    };
    const deps = makeTestDeps([provider]);
    const opts = makeTestOpts();
    const result = await reportQuotas(deps, opts);
    if (Object.keys(result.errors).length === 0 && result.rendered !== '') {
      console.log('PASS: single provider success');
      passed++;
    } else {
      console.log('FAIL: single provider success', result);
      failed++;
    }
  }

  // Test 3: One provider fails, another succeeds
  {
    const q2 = makeQuotaData({ id: 'provider2', providerName: 'SuccessProvider', used: 30.0, limit: 90.0 });
    const failingProvider = {
      id: 'provider1',
      displayName: 'Failing Provider',
      category: 'test',
      authStrategy: 'api',
      isAvailable: async () => true,
      fetchQuotas: async () => { throw new Error('Network timeout'); },
    };
    const successProvider = {
      id: 'provider2',
      displayName: 'Success Provider',
      category: 'test',
      authStrategy: 'api',
      isAvailable: async () => true,
      fetchQuotas: async () => [q2],
    };
    const deps = makeTestDeps([failingProvider, successProvider]);
    const opts = makeTestOpts();
    const result = await reportQuotas(deps, opts);
    if (result.errors['provider1'] && result.errors['provider1'].includes('Network timeout') && result.rendered !== '') {
      console.log('PASS: one fails, one succeeds');
      passed++;
    } else {
      console.log('FAIL: one fails, one succeeds', result);
      failed++;
    }
  }

  // Test 4: empty aggregatedGroups (backward-compat) — passes all raw data through
  {
    const q1 = makeQuotaData({ id: 'p1/req', providerName: 'P1', used: 50.0, limit: 100.0 });
    const q2 = makeQuotaData({ id: 'p2/req', providerName: 'P2', used: 70.0, limit: 100.0 });
    const provider1 = {
      id: 'p1', displayName: 'P1', category: 'test', authStrategy: 'api',
      isAvailable: async () => true,
      fetchQuotas: async () => [q1],
    };
    const provider2 = {
      id: 'p2', displayName: 'P2', category: 'test', authStrategy: 'api',
      isAvailable: async () => true,
      fetchQuotas: async () => [q2],
    };
    const deps = makeTestDeps([provider1, provider2]);
    // aggregatedGroups is empty → pipeline falls back to raw data
    const result = await reportQuotas(deps, makeTestOpts());
    if (result.rendered !== '' && result.rendered.includes('[█████') && result.rendered.includes('[███████')) {
      console.log('PASS: empty aggregatedGroups passes all raw data through');
      passed++;
    } else {
      console.log('FAIL: empty aggregatedGroups', result.rendered);
      failed++;
    }
  }

  // Test 5: providerId filter restricts to single provider
  {
    const q1 = makeQuotaData({ id: 'p1/req', providerName: 'P1', used: 50.0, limit: 100.0 });
    const q2 = makeQuotaData({ id: 'p2/req', providerName: 'P2', used: 70.0, limit: 100.0 });
    const provider1 = {
      id: 'p1', displayName: 'P1', category: 'test', authStrategy: 'api',
      isAvailable: async () => true,
      fetchQuotas: async () => [q1],
    };
    const provider2 = {
      id: 'p2', displayName: 'P2', category: 'test', authStrategy: 'api',
      isAvailable: async () => true,
      fetchQuotas: async () => [q2],
    };
    const deps = makeTestDeps([provider1, provider2]);
    const result = await reportQuotas(deps, makeTestOpts({ providerId: 'p1' }));
    if (result.rendered !== '' && result.rendered.includes('[█████')) {
      console.log('PASS: providerId filter restricts to single provider');
      passed++;
    } else {
      console.log('FAIL: providerId filter', result.rendered);
      failed++;
    }
  }

  console.log(`\nResults: ${passed} passed, ${failed} failed`);
  process.exit(failed > 0 ? 1 : 0);
}

runTests().catch(err => {
  console.error('Test error:', err);
  process.exit(1);
});
