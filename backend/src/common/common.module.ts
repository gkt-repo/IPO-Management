import { Global, Module } from '@nestjs/common';
import { EncryptionService } from './encryption.service';
import { JwtAuthGuard } from './jwt-auth.guard';

@Global()
@Module({
  providers: [EncryptionService, JwtAuthGuard],
  exports: [EncryptionService, JwtAuthGuard],
})
export class CommonModule {}
