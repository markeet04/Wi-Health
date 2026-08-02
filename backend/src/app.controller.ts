import { Body, Controller, Delete, Get, Headers, Param, Patch, Post, UnauthorizedException } from '@nestjs/common'
import {
  AppService,
  type AdminSettingsResponse,
  type DeviceAssignRequest,
  type LoginRequest,
  type UserMutationRequest,
} from './app.service'

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

  @Post('admin/complaints/:complaintId/messages')
  sendComplaintMessage(
    @Param('complaintId') complaintId: string,
    @Body() body: { text: string },
    @Headers('authorization') authorization?: string,
  ) {
    const token = bearerToken(authorization)
    if (!token) {
      throw new UnauthorizedException('Missing bearer token.')
    }

    return this.appService.sendComplaintMessage(token, complaintId, body)
  }

  @Patch('admin/complaints/:complaintId/resolve')
  resolveComplaint(@Param('complaintId') complaintId: string, @Headers('authorization') authorization?: string) {
    const token = bearerToken(authorization)
    if (!token) {
      throw new UnauthorizedException('Missing bearer token.')
    }

    return this.appService.resolveComplaint(token, complaintId)
  }

  // Module 4: mint a Firebase custom token for an ESP32 sensor (admin-only).
  // The token (uid=deviceId, claim device=true) is flashed to the uploader
  // board so it can authenticate and write /devices/$deviceId/live.
  @Post('admin/devices/:deviceId/token')
  mintDeviceToken(@Param('deviceId') deviceId: string, @Headers('authorization') authorization?: string) {
    const token = bearerToken(authorization)
    if (!token) {
      throw new UnauthorizedException('Missing bearer token.')
    }

    return this.appService.mintDeviceToken(token, deviceId)
  }

  // Module 8: device -> patient -> App User assignment (admin-only).
  @Get('admin/devices')
  listDevices(@Headers('authorization') authorization?: string) {
    const token = bearerToken(authorization)
    if (!token) {
      throw new UnauthorizedException('Missing bearer token.')
    }

    return this.appService.listDevices(token)
  }

  @Post('admin/devices/:deviceId/assign')
  assignDevice(
    @Param('deviceId') deviceId: string,
    @Body() body: DeviceAssignRequest,
    @Headers('authorization') authorization?: string,
  ) {
    const token = bearerToken(authorization)
    if (!token) {
      throw new UnauthorizedException('Missing bearer token.')
    }

    return this.appService.assignDevice(token, deviceId, body)
  }

  @Post('admin/devices/:deviceId/unassign')
  unassignDevice(@Param('deviceId') deviceId: string, @Headers('authorization') authorization?: string) {
    const token = bearerToken(authorization)
    if (!token) {
      throw new UnauthorizedException('Missing bearer token.')
    }

    return this.appService.unassignDevice(token, deviceId)
  }

  @Post('admin/device-requests/:requestId/decline')
  declineDeviceRequest(
    @Param('requestId') requestId: string,
    @Headers('authorization') authorization?: string,
  ) {
    const token = bearerToken(authorization)
    if (!token) {
      throw new UnauthorizedException('Missing bearer token.')
    }

    return this.appService.declineDeviceRequest(token, requestId)
  }
}