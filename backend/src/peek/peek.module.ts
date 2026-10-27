import { Module } from '@nestjs/common';
import { PeekService } from './peek.service';

@Module({
  providers: [PeekService],
  exports: [PeekService],
})
export class PeekModule {}
