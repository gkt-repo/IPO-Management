import { Test } from '@nestjs/testing';
import request = require('supertest');
import { AppModule } from '../app.module';
import { PrismaService } from '../prisma/prisma.service';
import { AuthService } from './auth.service';
import { IpoService } from '../ipo/ipo.service';
import { CatalogueService } from '../ipo/catalogue.service';
import { RefreshService } from '../refresh/refresh.service';

it('enforces authentication throttling through the actual app guard registration', async () => {
  const auth = { login: jest.fn(async () => ({ accessToken: 'test' })) };
  const module = await Test.createTestingModule({ imports: [AppModule] })
    .overrideProvider(PrismaService).useValue({})
    .overrideProvider(AuthService).useValue(auth)
    .overrideProvider(IpoService).useValue({})
    .overrideProvider(CatalogueService).useValue({})
    .overrideProvider(RefreshService).useValue({})
    .compile();
  const app = module.createNestApplication();
  // Match the documented one-hop Nginx deployment.
  app.getHttpAdapter().getInstance().set('trust proxy', 1);
  await app.init();
  try {
    for (let i = 0; i < 10; i++) {
      await request(app.getHttpServer()).post('/api/auth/login').set('X-Forwarded-For', '203.0.113.1').send({ email: 'test@example.test', password: 'test' }).expect(200);
    }
    await request(app.getHttpServer()).post('/api/auth/login').set('X-Forwarded-For', '203.0.113.1').send({ email: 'test@example.test', password: 'test' }).expect(429);
    await request(app.getHttpServer()).post('/api/auth/login').set('X-Forwarded-For', '203.0.113.2')
      .send({ email: 'other@example.test', password: 'test' }).expect(200);
    expect(auth.login).toHaveBeenCalledTimes(11);
  } finally { await app.close(); }
});
