import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_user.dart';
import 'auth/seller_join_screen.dart';
import 'seller/seller_shell.dart';

class MainShell extends StatelessWidget {
  const MainShell({super.key});

  @override
  Widget build(BuildContext context) {
    final appUser = context.watch<AppUser>();
    if (appUser.isSeller && appUser.joinStatus != 'active') {
      return const SellerJoinScreen();
    }
    return const SellerShell();
  }
}
