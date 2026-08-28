import 'package:flutter/material.dart';

import '../design/tokens.dart';

class SideMenu extends StatelessWidget {
  const SideMenu({super.key});

  static const _items = <(String, String?)>[
    ('支付設定', '支付方式／發票載具'),
    ('歷史訂單', null),
    ('優惠管理', '輸入兌換碼／查看剩餘時數／查看折抵券'),
    ('訂閱管理', null),
    ('未繳費用', null),
  ];

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFFFAFAFA),
      width: MediaQuery.sizeOf(context).width * 0.82,
      shape: const RoundedRectangleBorder(),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _header(context),
          _proRow(),
          _walletRow(),
          const SizedBox(height: 12),
          for (final (title, sub) in _items) _menuRow(title, sub),
          const SizedBox(height: 8),
          const _RewardBanner(),
          const SizedBox(height: 12),
          const _ReferralBanner(),
          const SizedBox(height: 28),
          const _FooterLinks(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Container(
      color: const Color(0xFF3B3B3B),
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(12, 6, 16, 6),
                decoration: const BoxDecoration(
                  color: Color(0xFF5A5A5A),
                  borderRadius: BorderRadius.horizontal(
                    right: Radius.circular(AppRadius.pill),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(
                      Icons.stars_rounded,
                      color: Color(0xFFF5C542),
                      size: 24,
                    ),
                    SizedBox(width: 8),
                    Text(
                      '我的成就',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              const Padding(
                padding: EdgeInsets.only(right: 20),
                child: Icon(
                  Icons.notifications_none,
                  color: Colors.white,
                  size: 26,
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 22, 20, 24),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Hi, 陳O誠',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.white70, size: 26),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _proRow() {
    return Container(
      color: const Color(0xFFFDEBEC),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: AppColor.brandBright,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'PRO',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              '成為 PRO 會員',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColor.brand,
              ),
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColor.brand, size: 24),
        ],
      ),
    );
  }

  Widget _walletRow() {
    return Container(
      color: const Color(0xFFF0F0F0),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '和雲錢包',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColor.textPrimary,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '開通錢包 立即儲值',
                  style: TextStyle(fontSize: 14, color: AppColor.textSecondary),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right,
            color: AppColor.textSecondary,
            size: 24,
          ),
        ],
      ),
    );
  }

  Widget _menuRow(String title, String? sub) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 9),
            width: 5,
            height: 5,
            color: AppColor.textPrimary,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColor.textPrimary,
                      ),
                    ),
                    if (title == '訂閱管理') ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5A623),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.search, size: 15, color: Colors.white),
                            SizedBox(width: 5),
                            Text(
                              '用車更划算！',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                if (sub != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    sub,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColor.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RewardBanner extends StatelessWidget {
  const _RewardBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFDE4EA), Color(0xFFFBD3DE)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFF06292),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Icon(
              Icons.directions_car,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              '時時回饋計畫',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFFD5305C),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFE8365E),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: const Text(
              '點我換好禮！',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReferralBanner extends StatelessWidget {
  const _ReferralBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3DC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.card_giftcard, color: Color(0xFFF5A623), size: 32),
          SizedBox(width: 12),
          Text(
            '推薦好友領折抵券',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: Color(0xFFCF8A1B),
            ),
          ),
        ],
      ),
    );
  }
}

class _FooterLinks extends StatelessWidget {
  const _FooterLinks();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '關於 iRent',
          style: TextStyle(fontSize: 16, color: AppColor.textSecondary),
        ),
        SizedBox(width: 16),
        Text('|', style: TextStyle(fontSize: 16, color: AppColor.divider)),
        SizedBox(width: 16),
        Text(
          '聯絡我們',
          style: TextStyle(fontSize: 16, color: AppColor.textSecondary),
        ),
      ],
    );
  }
}
