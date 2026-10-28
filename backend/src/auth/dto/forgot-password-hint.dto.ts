import { IsEmail } from 'class-validator';

export class ForgotPasswordHintDto {
  @IsEmail({}, { message: 'Please provide a valid email address' })
  email: string;
}
