import { Test, TestingModule } from '@nestjs/testing';
import { AuthService } from './auth.service';
import { PrismaService } from '../prisma/prisma.service';
import { JwtService } from '@nestjs/jwt';

describe('AuthService - Password Hint', () => {
  let service: AuthService;
  let prisma: any;

  beforeEach(async () => {
    prisma = {
      user: {
        findUnique: jest.fn(),
        create: jest.fn(),
      },
    };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        AuthService,
        {
          provide: PrismaService,
          useValue: prisma,
        },
        {
          provide: JwtService,
          useValue: {
            sign: jest.fn().mockReturnValue('mock_jwt_token'),
          },
        },
      ],
    }).compile();

    service = module.get<AuthService>(AuthService);
  });

  it('should register a user with passwordHint', async () => {
    prisma.user.findUnique.mockResolvedValue(null);
    prisma.user.create.mockResolvedValue({
      id: 'u1',
      email: 'investor@example.com',
      fullName: 'Investor One',
      role: 'USER',
      createdAt: new Date(),
    });

    const result = await service.register({
      email: 'investor@example.com',
      password: 'password123',
      fullName: 'Investor One',
      passwordHint: 'My dog Fluffy',
    });

    expect(prisma.user.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          email: 'investor@example.com',
          passwordHint: 'My dog Fluffy',
        }),
      }),
    );
    expect(result.accessToken).toBe('mock_jwt_token');
  });

  it('should return hint when account has a password hint', async () => {
    prisma.user.findUnique.mockResolvedValue({
      passwordHint: 'First high school teacher',
    });

    const result = await service.getPasswordHint('test@example.com');
    expect(result.hint).toBe('First high school teacher');
    expect(result.message).toContain('successfully');
  });

  it('should return message when account has no password hint', async () => {
    prisma.user.findUnique.mockResolvedValue({
      passwordHint: null,
    });

    const result = await service.getPasswordHint('nohint@example.com');
    expect(result.hint).toBeNull();
    expect(result.message).toContain('No password hint was set');
  });

  it('should return message when account does not exist', async () => {
    prisma.user.findUnique.mockResolvedValue(null);

    const result = await service.getPasswordHint('unknown@example.com');
    expect(result.hint).toBeNull();
    expect(result.message).toContain('No account registered');
  });
});
