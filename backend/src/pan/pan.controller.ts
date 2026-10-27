import { Controller, Post, Get, Delete, Body, UseGuards } from '@nestjs/common';
import { PanService } from './pan.service';
import { SavePanDto } from './dto/save-pan.dto';
import { JwtAuthGuard } from '../common/jwt-auth.guard';
import { CurrentUser } from '../common/current-user.decorator';

@UseGuards(JwtAuthGuard)
@Controller('api/pan')
export class PanController {
  constructor(private readonly panService: PanService) {}

  @Post()
  async savePan(@CurrentUser() user: { id: string }, @Body() dto: SavePanDto) {
    return this.panService.savePan(user.id, dto);
  }

  @Get()
  async getSavedPan(@CurrentUser() user: { id: string }) {
    return this.panService.getSavedPan(user.id);
  }

  @Delete()
  async deleteSavedPan(@CurrentUser() user: { id: string }) {
    return this.panService.deleteSavedPan(user.id);
  }
}
