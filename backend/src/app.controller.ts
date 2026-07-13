import { Body, Controller, Get, Headers, Post, UnauthorizedException } from '@nestjs/common'
import { AppService, type LoginRequest } from './app.service'

function bearerToken(authorization?: string) {
  if (!authorization) return ''
  const [scheme, token] = authorization.split(' ')
  return scheme === 'Bearer' ? token ?? '' : ''
}

@Controller()
export class AppController {
  constructor(private readonly appService: AppService) {}

  @Get('health')
  health() {
    return this.appService.health()
  }

  @Post('auth/login')
  login(@Body() body: LoginRequest) {
    return this.appService.login(body)
  }

  @Get('auth/session')
  async session(@Headers('authorization') authorization?: string) {
    const token = bearerToken(authorization)
    if (!token) {
      throw new UnauthorizedException('Missing bearer token.')
    }

    return this.appService.restoreSession(token)
  }

  @Post('auth/logout')
  logout(@Headers('authorization') authorization?: string) {
    const token = bearerToken(authorization)
    if (!token) {
      throw new UnauthorizedException('Missing bearer token.')
    }

    this.appService.logout(token)
    return { ok: true }
  }

  @Get('admin/dashboard')
  dashboard(@Headers('authorization') authorization?: string) {
    const token = bearerToken(authorization)
    if (!token) {
      throw new UnauthorizedException('Missing bearer token.')
    }

    return this.appService.getDashboard(token)
  }
}