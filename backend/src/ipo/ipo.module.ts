import { Module } from '@nestjs/common';
import { CatalogueService } from './catalogue.service';
import { IpoService } from './ipo.service';
import { IpoController } from './ipo.controller';
import { MarketPriceService } from './market-price.service';
import { RefreshService } from '../refresh/refresh.service';
import { RefreshController } from '../refresh/refresh.controller';
import { PanModule } from '../pan/pan.module';
import { PeekModule } from '../peek/peek.module';

@Module({
  imports: [PanModule, PeekModule],
  controllers: [IpoController, RefreshController],
  providers: [CatalogueService, IpoService, MarketPriceService, RefreshService],
  exports: [IpoService, MarketPriceService, RefreshService],
})
export class IpoModule {}
