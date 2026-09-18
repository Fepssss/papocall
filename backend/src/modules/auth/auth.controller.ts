import { Request, Response, NextFunction } from 'express';
import { authService } from './auth.service';
import {
  RegisterSchema,
  LoginSchema,
  RefreshTokenSchema,
  LogoutSchema,
  VerifyEmailSchema,
  ForgotPasswordSchema,
  ResetPasswordSchema,
  UsernameAvailableSchema,
  ChangeUsernameSchema,
} from './auth.schemas';

export class AuthController {
  /**
   * POST /auth/register
   */
  async register(req: Request, res: Response, next: NextFunction): Promise<void> {
    try {
      const data = RegisterSchema.parse(req.body);
      const ip = req.ip || req.socket.remoteAddress;

      const result = await authService.register({
        email: data.email,
        username: data.username,
        displayName: data.displayName,
        password: data.password,
        ip,
      });

      res.status(201).json({
        success: true,
        data: result,
      });
    } catch (error) {
      next(error);
    }
  }

  /**
   * GET /auth/username-available?username=joaosilva
   */
  async checkUsernameAvailable(req: Request, res: Response, next: NextFunction): Promise<void> {
    try {
      const data = UsernameAvailableSchema.parse({
        username: req.query.username,
      });

      const result = await authService.checkUsernameAvailability(data.username);

      res.status(200).json({
        success: true,
        data: result,
      });
    } catch (error) {
      next(error);
    }
  }

  /**
   * POST /auth/login
   */
  async login(req: Request, res: Response, next: NextFunction): Promise<void> {
    try {
      const data = LoginSchema.parse(req.body);
      const ip = req.ip || req.socket.remoteAddress;

      const result = await authService.login({
        identifier: data.identifier,
        password: data.password,
        ip,
      });

      res.status(200).json({
        success: true,
        data: result,
      });
    } catch (error) {
      next(error);
    }
  }

  /**
   * POST /auth/refresh
   */
  async refresh(req: Request, res: Response, next: NextFunction): Promise<void> {
    try {
      const data = RefreshTokenSchema.parse(req.body);
      const ip = req.ip || req.socket.remoteAddress;

      const result = await authService.refreshAccessToken(data.refreshToken, ip);

      res.status(200).json({
        success: true,
        data: result,
      });
    } catch (error) {
      next(error);
    }
  }

  /**
   * POST /auth/logout
   */
  async logout(req: Request, res: Response, next: NextFunction): Promise<void> {
    try {
      const data = LogoutSchema.parse(req.body);
      const ip = req.ip || req.socket.remoteAddress;

      await authService.logout(data.refreshToken, ip);

      res.status(200).json({
        success: true,
        data: { message: 'Sessão encerrada com sucesso.' },
      });
    } catch (error) {
      next(error);
    }
  }

  /**
   * POST /auth/logout-all
   */
  async logoutAll(req: Request, res: Response, next: NextFunction): Promise<void> {
    try {
      const userId = req.userId!;
      const ip = req.ip || req.socket.remoteAddress;

      await authService.logoutAllSessions(userId, ip);

      res.status(200).json({
        success: true,
        data: { message: 'Todas as sessões ativas foram revogadas com sucesso.' },
      });
    } catch (error) {
      next(error);
    }
  }

  /**
   * POST /auth/verify-email
   */
  async verifyEmail(req: Request, res: Response, next: NextFunction): Promise<void> {
    try {
      const data = VerifyEmailSchema.parse(req.body);
      const ip = req.ip || req.socket.remoteAddress;

      const result = await authService.verifyEmail(data.token, ip);

      res.status(200).json({
        success: true,
        data: result,
      });
    } catch (error) {
      next(error);
    }
  }

  /**
   * POST /auth/forgot-password
   */
  async forgotPassword(req: Request, res: Response, next: NextFunction): Promise<void> {
    try {
      const data = ForgotPasswordSchema.parse(req.body);
      const ip = req.ip || req.socket.remoteAddress;

      const result = await authService.forgotPassword(data.email, ip);

      res.status(200).json({
        success: true,
        data: result,
      });
    } catch (error) {
      next(error);
    }
  }

  /**
   * POST /auth/reset-password
   */
  async resetPassword(req: Request, res: Response, next: NextFunction): Promise<void> {
    try {
      const data = ResetPasswordSchema.parse(req.body);
      const ip = req.ip || req.socket.remoteAddress;

      const result = await authService.resetPassword(data.token, data.newPassword, ip);

      res.status(200).json({
        success: true,
        data: result,
      });
    } catch (error) {
      next(error);
    }
  }

  /**
   * PATCH /auth/username
   */
  async changeUsername(req: Request, res: Response, next: NextFunction): Promise<void> {
    try {
      const data = ChangeUsernameSchema.parse(req.body);
      const userId = req.userId!;
      const ip = req.ip || req.socket.remoteAddress;

      const user = await authService.changeUsername(userId, data.newUsername, ip);

      res.status(200).json({
        success: true,
        data: { user },
      });
    } catch (error) {
      next(error);
    }
  }

  /**
   * GET /auth/me
   */
  async getMe(req: Request, res: Response, next: NextFunction): Promise<void> {
    try {
      const userId = req.userId!;
      const user = await authService.getMe(userId);

      res.status(200).json({
        success: true,
        data: { user },
      });
    } catch (error) {
      next(error);
    }
  }
}

export const authController = new AuthController();
