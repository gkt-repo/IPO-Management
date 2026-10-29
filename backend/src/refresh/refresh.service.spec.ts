import { RefreshService } from './refresh.service';
import { PanService } from '../pan/pan.service';

const flush = () => new Promise<void>(resolve => setImmediate(resolve));
const ipo = { id: 'ipo-1', name: 'Example', registrar: 'KFINTECH', isActive: true };
const result = { status: 'ALLOTTED', sharesAllotted: 10, source: 'TEST', message: 'Shares allotted' };

// Transaction queue models the per-user PostgreSQL row lock. No registrar call
// occurs while this lock is held, so PAN replacement can race an open request.
function fixture() {
  let savedPan: any = { id: 'pan-old', userId: 'user', encryptedPan: 'ABCDE1234F' };
  let check: any = { savedPanId: 'pan-old', ipoId: ipo.id, ipo, hasApplied: true, status: 'PENDING' };
  let queue = Promise.resolve();
  const jobs: any[] = [], history: any[] = [];
  const matches = (job: any, where: any) => (!where.id || job.id === where.id) &&
    (!where.userId || job.userId === where.userId) &&
    (!where.status || (typeof where.status === 'string' ? job.status === where.status : where.status.in.includes(job.status))) &&
    (!where.heartbeatAt?.lt || job.heartbeatAt < where.heartbeatAt.lt) &&
    (!where.heartbeatAt?.gte || job.heartbeatAt >= where.heartbeatAt.gte);
  const db: any = {
    $queryRaw: jest.fn(async () => []),
    $transaction: jest.fn(fn => {
      const run = queue.then(() => fn(db));
      queue = run.then(() => undefined, () => undefined);
      return run;
    }),
    savedPan: {
      findUnique: jest.fn(async () => savedPan),
      delete: jest.fn(async () => { savedPan = null; check = null; history.length = 0; }),
      create: jest.fn(async ({ data }) => savedPan = { id: 'pan-new', ...data }),
    },
    refreshJob: {
      findFirst: jest.fn(async ({ where }) => jobs.find(j => matches(j, where)) ?? null),
      create: jest.fn(async ({ data }) => { const j = { id: `job-${jobs.length}`, ...data }; jobs.push(j); return j; }),
      updateMany: jest.fn(async ({ where, data }) => {
        const targets = jobs.filter(j => matches(j, where));
        targets.forEach(j => Object.assign(j, data)); return { count: targets.length };
      }),
    },
    allotmentCheck: {
      findMany: jest.fn(async () => check ? [check] : []),
      findUnique: jest.fn(async () => check),
      updateMany: jest.fn(async ({ where, data }) => {
        if (!check || check.savedPanId !== where.savedPanId || !check.hasApplied || check.status === 'ALLOTTED') return { count: 0 };
        Object.assign(check, data); return { count: 1 };
      }),
    },
    allotmentHistory: { create: jest.fn(async ({ data }) => { history.push(data); }) },
  };
  const encryption: any = { sanitizePan: x => x, encryptPan: x => x, decryptPan: x => x, maskPan: () => 'masked', generateHmacFingerprint: x => x };
  const pan = new PanService(db, encryption);
  const peek: any = { checkAllotment: jest.fn(async () => result) };
  const service = new RefreshService(db, pan, peek);
  return { db, pan, peek, service, jobs, history, getCheck: () => check };
}

describe('refresh admission and recovery', () => {
  it('deduplicates two concurrent requests, even from separate service instances', async () => {
    const f = fixture();
    const second = new RefreshService(f.db, f.pan, f.peek);
    const [a, b] = await Promise.all([f.service.triggerRefresh('user', true), second.triggerRefresh('user', true)]);
    expect(a.jobId).toBe(b.jobId);
    expect(b.isDuplicate).toBe(true);
    expect(f.jobs).toHaveLength(1);
    expect(f.db.$queryRaw).toHaveBeenCalled();
    await flush();
    expect(f.peek.checkAllotment).toHaveBeenCalledTimes(1);
    expect(f.jobs[0].status).toBe('COMPLETED');
  });

  it.each(['replace', 'delete'])('discards an old-PAN result after %s during lookup', async action => {
    const f = fixture();
    let release!: (value: any) => void;
    f.peek.checkAllotment.mockImplementation(() => new Promise(r => { release = r; }));
    await f.service.triggerRefresh('user', true);
    await flush();
    if (action === 'replace') await f.pan.savePan('user', { pan: 'XYZPA5678Q', consent: true, confirmReplace: true });
    else await f.pan.deleteSavedPan('user');
    release(result);
    await flush();
    expect(f.getCheck()).toBeNull();
    expect(f.history).toHaveLength(0);
    expect(f.jobs[0].status).toBe('FAILED');
  });

  it('marks a progress-write failure FAILED and allows a new refresh', async () => {
    const f = fixture();
    const update = f.db.refreshJob.updateMany.getMockImplementation();
    f.db.refreshJob.updateMany.mockImplementation(async args => {
      if ('processedIpos' in args.data) throw new Error('database interrupted');
      return update(args);
    });
    await f.service.triggerRefresh('user', true);
    await flush();
    expect(f.jobs[0].status).toBe('FAILED');
    f.db.refreshJob.updateMany.mockImplementation(update);
    const next = await f.service.triggerRefresh('user', true);
    expect(next.jobId).not.toBe(f.jobs[0].id);
    await flush();
  });

  it('expires a crashed worker and rejects its delayed result after recovery', async () => {
    const f = fixture();
    let release!: (value: any) => void;
    f.peek.checkAllotment.mockImplementationOnce(() => new Promise(r => { release = r; }));
    await f.service.triggerRefresh('user', true);
    await flush();
    f.jobs[0].heartbeatAt = new Date(Date.now() - 121_000);
    const progress = await f.service.getJobProgress(f.jobs[0].id, 'user');
    expect(progress.status).toBe('FAILED');
    const next = await f.service.triggerRefresh('user', true);
    expect(next.jobId).not.toBe(f.jobs[0].id);
    release({ ...result, sharesAllotted: 999 });
    await flush();
    expect(f.getCheck().allottedQuantity).toBe(10);
    expect(f.history).toHaveLength(1);
  });

  it('keeps confirmed allotments when another result arrives late', async () => {
    const f = fixture();
    let release!: (value: any) => void;
    f.peek.checkAllotment.mockImplementation(() => new Promise(r => { release = r; }));
    await f.service.triggerRefresh('user', true);
    await flush();
    Object.assign(f.getCheck(), { status: 'ALLOTTED', allottedQuantity: 20 });
    release({ ...result, status: 'LOOKUP_FAILED', sharesAllotted: null });
    await flush();
    expect(f.getCheck().status).toBe('ALLOTTED');
    expect(f.getCheck().allottedQuantity).toBe(20);
    expect(f.history).toHaveLength(0);
  });

  it('respects cooldown for settled checks', async () => {
    const f = fixture();
    f.getCheck().status = 'NOT_ALLOTTED';
    f.jobs.push({ id: 'recent', userId: 'user', status: 'COMPLETED', completedAt: new Date() });
    const response = await f.service.triggerRefresh('user');
    expect(response.jobId).toBe('recent');
    expect(response.cooldownRemainingSeconds).toBeGreaterThan(0);
  });
});
