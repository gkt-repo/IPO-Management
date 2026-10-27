import { Module } from '@nestjs/common';
import { PanService } from './pan.service';
import { PanController } from './pan.controller';

@Module({
  controllers: [PanController],
  providers: [PanService],
  exports: [PanService],
})
export class PanModule {}
