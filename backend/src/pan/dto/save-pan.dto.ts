import { IsBoolean, IsNotEmpty, IsOptional, IsString, Matches } from 'class-validator';

export class SavePanDto {
  @IsString()
  @IsNotEmpty({ message: 'PAN number is required' })
  @Matches(/^[A-Z]{5}[0-9]{4}[A-Z]{1}$/i, {
    message: 'Invalid Indian PAN format. Expected format: ABCDE1234F',
  })
  pan: string;

  @IsBoolean({ message: 'Explicit consent is required to process and verify your PAN' })
  consent: boolean;

  @IsOptional()
  @IsBoolean()
  confirmReplace?: boolean;
}
