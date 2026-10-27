import { Controller, Get, Param, Query, UseGuards } from '@nestjs/common';
import { IpoService } from './ipo.service';
import { JwtAuthGuard } from '../common/jwt-auth.guard';
import { CurrentUser } from '../common/current-user.decorator';

@UseGuards(JwtAuthGuard)
@Controller('api/ipo')
export class IpoController {
  constructor(private readonly ipoService: IpoService) {}

  @Get()
  async listIpos(
    @CurrentUser() user: { id: string },
    @Query('status') status?: string,
    @Query('issueType') issueType?: string,
    @Query('search') search?: string,
  ) {
    return this.ipoService.listIpos(user.id, { status, issueType, search });
  }

  @Get('dashboard')
  async getDashboardSummary(@CurrentUser() user: { id: string }) {
    return this.ipoService.getDashboardSummary(user.id);
  }

  @Get(':id')
  async getIpoDetails(
    @Param('id') id: string,
    @CurrentUser() user: { id: string },
  ) {
    return this.ipoService.getIpoDetails(id, user.id);
  }
}
