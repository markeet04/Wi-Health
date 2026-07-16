import { Body, Controller, Delete, Get, Headers, Param, Patch, Post, UnauthorizedException } from '@nestjs/common'
import { AppService, type AdminSettingsResponse, type LoginRequest, type UserMutationRequest } from './app.service'

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

  @Get('admin/settings')
  settings(@Headers('authorization') authorization?: string) {
    const token = bearerToken(authorization)
    if (!token) {
      throw new UnauthorizedException('Missing bearer token.')
    }

    return this.appService.getSettings(token)
  }

  @Patch('admin/settings')
  updateSettings(@Body() body: Partial<AdminSettingsResponse>, @Headers('authorization') authorization?: string) {
    const token = bearerToken(authorization)
    if (!token) {
      throw new UnauthorizedException('Missing bearer token.')
    }

    return this.appService.updateSettings(token, body)
  }

  @Get('admin/users')
  listUsers(@Headers('authorization') authorization?: string) {
    const token = bearerToken(authorization)
    if (!token) {
      throw new UnauthorizedException('Missing bearer token.')
    }

    return this.appService.listUsers(token)
  }

  @Post('admin/users')
  createUser(@Body() body: UserMutationRequest, @Headers('authorization') authorization?: string) {
    const token = bearerToken(authorization)
    if (!token) {
      throw new UnauthorizedException('Missing bearer token.')
    }

    return this.appService.createUser(token, body)
  }

  @Patch('admin/users/:uid')
  updateUser(@Param('uid') uid: string, @Body() body: UserMutationRequest, @Headers('authorization') authorization?: string) {
    const token = bearerToken(authorization)
    if (!token) {
      throw new UnauthorizedException('Missing bearer token.')
    }

    return this.appService.updateUser(token, uid, body)
  }

  @Delete('admin/users/:uid')
  deleteUser(@Param('uid') uid: string, @Headers('authorization') authorization?: string) {
    const token = bearerToken(authorization)
    if (!token) {
      throw new UnauthorizedException('Missing bearer token.')
    }

    return this.appService.deleteUser(token, uid)
  }
}