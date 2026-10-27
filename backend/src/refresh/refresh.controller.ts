import { Controller, Post, Get, Param, Query, UseGuards } from '@nestjs/common';
import { RefreshService } from './refresh.service';
import { JwtAuthGuard } from '../common/jwt-auth.guard';
import { CurrentUser } from '../common/current-user.decorator';

@UseGuards(JwtAuthGuard)
@Controller('api/ipo/refresh')
export class RefreshController {
  constructor(private readonly refreshService: RefreshService) {}

  @Post()
  async triggerRefresh(
    @CurrentUser() user: { id: string },
    @Query('force') force?: string,
  ) {
    const isForce = force === 'true' || force === '1';
    return this.refreshService.triggerRefresh(user.id, isForce);
  }

  @Get(':jobId')
  async getJobProgress(
    @Param('jobId') jobId: string,
    @CurrentUser() user: { id: string },
  ) {
    return this.refreshService.getJobProgress(jobId, user.id);
  }
}
