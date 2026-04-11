import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../domain/auth_provider.dart';

// ── Odisha hub pincodes ───────────────────────────────────────────────────────

const _odishaHubs = <String, String>{
  '751001': 'Bhubaneswar HQ',
  '753001': 'Cuttack Central',
  '769001': 'Rourkela North',
  '768001': 'Sambalpur Depot',
  '760001': 'Berhampur South',
  '756001': 'Balasore East',
  '757001': 'Baripada Hub',
  '768201': 'Jharsuguda Industrial',
  '759001': 'Angul Hub',
  '754211': 'Kendrapara Depot',
  '764020': 'Koraput Tribal',
  '752001': 'Puri Coastal',
  '765001': 'Rayagada Hub',
  '770001': 'Sundargarh Steel Belt',
  '761001': 'Phulbani Hub',
  '766001': 'Bhawanipatna Hub',
};

const _vehicleTypes = <String, String>{
  'bike': 'Bike / Motorcycle',
  'three_wheeler': 'Three-Wheeler (Auto)',
  'van': 'Van / Mini-Truck',
  'truck': 'Heavy Truck',
};

// ── Screen ────────────────────────────────────────────────────────────────────

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();

  // Common controllers
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();

  // Driver controllers
  final _licenseCtrl = TextEditingController();

  // Hub operator controller
  final _companyCtrl = TextEditingController();

  // Manager controller
  final _orgCtrl = TextEditingController();

  String _role = 'driver';
  String? _vehicleType;
  String? _selectedHubPin;

  // OTP state
  bool _otpSent = false;
  String? _mockCode; // shown in dev mode
  final bool _otpVerified = false;

  bool _loading = false;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    _otpCtrl.dispose();
    _licenseCtrl.dispose();
    _orgCtrl.dispose();
    _companyCtrl.dispose();
    super.dispose();
  }

  // ── OTP ──────────────────────────────────────────────────────────────────────

  Future<void> _sendOtp() async {
    final phone = _phoneCtrl.text.trim();
    if (!RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(phone)) {
      setState(() =>
          _error = 'Enter a valid E.164 phone number (e.g. +919876543210)');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final result =
          await ref.read(authNotifierProvider.notifier).sendOtp(phone: phone);
      setState(() {
        _otpSent = true;
        _mockCode = result['mock'] == true ? result['code'] as String? : null;
      });
    } catch (e) {
      setState(() => _error = _parseError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ── Signup ────────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_otpSent) {
      setState(() => _error = 'Please verify your phone number first');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authNotifierProvider.notifier).signup(
            email: _emailCtrl.text.trim(),
            password: _passCtrl.text,
            fullName: _nameCtrl.text.trim(),
            phone: _phoneCtrl.text.trim(),
            role: _role,
            otpCode: _otpCtrl.text.trim(),
            licenseNumber: _role == 'driver' ? _licenseCtrl.text.trim() : null,
            vehicleType: _role == 'driver' ? _vehicleType : null,
            assignedHubId: _role == 'gatekeeper' ? _selectedHubPin : null,
            hubName:
                _role == 'gatekeeper' ? _odishaHubs[_selectedHubPin] : null,
            organizationName: _role == 'manager'
                ? _orgCtrl.text.trim()
                : _role == 'gatekeeper'
                    ? _companyCtrl.text.trim()
                    : null,
          );
      if (mounted) {
        final role = ref.read(authNotifierProvider).role ?? _role;
        String dest = '/dashboard';
        if (role == 'driver') dest = '/driver';
        if (role == 'gatekeeper') dest = '/hub';
        context.go(dest);
      }
    } catch (e) {
      setState(() => _error = _parseError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _parseError(Object e) {
    final s = e.toString();
    // Extract DioException detail message if present
    final match = RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(s);
    return match?.group(1) ?? s;
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 32),

                  // ── Role selector ──────────────────────────────────────────
                  _RoleToggle(
                    selected: _role,
                    onChanged: (r) => setState(() {
                      _role = r;
                      _error = null;
                    }),
                  ),
                  const SizedBox(height: 24),

                  // ── Common fields ──────────────────────────────────────────
                  _Field(
                      ctrl: _nameCtrl,
                      label: 'Full Name',
                      hint: 'Ravi Kumar',
                      validator: (v) =>
                          (v?.trim().isEmpty ?? true) ? 'Required' : null),
                  const SizedBox(height: 14),
                  _Field(
                      ctrl: _emailCtrl,
                      label: 'Work Email',
                      hint: 'ravi@company.com',
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) => (v?.contains('@') ?? false)
                          ? null
                          : 'Enter a valid email'),
                  const SizedBox(height: 14),

                  // Phone + Send OTP row
                  _PhoneOtpRow(
                    phoneCtrl: _phoneCtrl,
                    sending: _sending,
                    otpSent: _otpSent,
                    mockCode: _mockCode,
                    onSend: _sendOtp,
                  ),
                  const SizedBox(height: 14),

                  // OTP field — shown after Send OTP
                  if (_otpSent) ...[
                    _Field(
                      ctrl: _otpCtrl,
                      label: 'Verification Code',
                      hint: '6-digit code',
                      keyboardType: TextInputType.number,
                      validator: (v) =>
                          (v?.length == 6) ? null : 'Enter the 6-digit code',
                    ),
                    const SizedBox(height: 14),
                  ],

                  _Field(
                      ctrl: _passCtrl,
                      label: 'Password',
                      hint: '••••••••',
                      obscureText: true,
                      validator: (v) =>
                          (v?.length ?? 0) >= 8 ? null : 'Min 8 characters'),
                  const SizedBox(height: 20),

                  // ── Role-specific fields ───────────────────────────────────
                  _RoleFields(
                    role: _role,
                    licenseCtrl: _licenseCtrl,
                    orgCtrl: _orgCtrl,
                    companyCtrl: _companyCtrl,
                    vehicleType: _vehicleType,
                    selectedHubPin: _selectedHubPin,
                    onVehicleChanged: (v) => setState(() => _vehicleType = v),
                    onHubChanged: (p) => setState(() => _selectedHubPin = p),
                  ),

                  // ── Error banner ───────────────────────────────────────────
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    _ErrorBanner(message: _error!),
                  ],

                  const SizedBox(height: 24),

                  // ── Submit ─────────────────────────────────────────────────
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.black))
                          : const Text('Create Account',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 15)),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Sign in link ───────────────────────────────────────────
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Text('Already have an account? ',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 13)),
                    GestureDetector(
                      onTap: () => context.go('/login'),
                      child: const Text('Sign In',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          )),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
              color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.loop, color: Colors.black, size: 20),
        ),
        const SizedBox(width: 10),
        const Text('Qubolt',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 20)),
      ]),
      const SizedBox(height: 8),
      const Text('Create your account',
          style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 22)),
      const SizedBox(height: 4),
      const Text('Join the supply chain network',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
    ]);
  }
}

// ── Role toggle ───────────────────────────────────────────────────────────────

class _RoleToggle extends StatelessWidget {
  const _RoleToggle({required this.selected, required this.onChanged});
  final String selected;
  final ValueChanged<String> onChanged;

  static const _roles = [
    ('driver', Icons.local_shipping_outlined, 'Driver'),
    ('gatekeeper', Icons.warehouse_outlined, 'Hub Operator'),
    ('manager', Icons.manage_accounts_outlined, 'Manager'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('I am a…',
          style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500)),
      const SizedBox(height: 8),
      Row(
          children: _roles.map((t) {
        final (role, icon, label) = t;
        final active = selected == role;
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(role),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: active
                    ? AppColors.primary.withOpacity(0.12)
                    : AppColors.cardBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: active ? AppColors.primary : AppColors.border,
                  width: active ? 1.5 : 1,
                ),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon,
                    color: active ? AppColors.primary : AppColors.textSecondary,
                    size: 20),
                const SizedBox(height: 4),
                Text(label,
                    style: TextStyle(
                      color:
                          active ? AppColors.primary : AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                    )),
              ]),
            ),
          ),
        );
      }).toList()),
    ]);
  }
}

// ── Phone + OTP send row ──────────────────────────────────────────────────────

class _PhoneOtpRow extends StatelessWidget {
  const _PhoneOtpRow({
    required this.phoneCtrl,
    required this.sending,
    required this.otpSent,
    required this.mockCode,
    required this.onSend,
  });
  final TextEditingController phoneCtrl;
  final bool sending;
  final bool otpSent;
  final String? mockCode;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Phone Number',
          style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500)),
      const SizedBox(height: 6),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: TextFormField(
            controller: phoneCtrl,
            keyboardType: TextInputType.phone,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: _inputDecoration('+919876543210'),
            validator: (v) =>
                RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(v?.trim() ?? '')
                    ? null
                    : 'E.164 format required (+91…)',
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: sending ? null : onSend,
            style: ElevatedButton.styleFrom(
              backgroundColor: otpSent ? AppColors.success : AppColors.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: sending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text(otpSent ? 'Resend' : 'Send OTP',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
      if (mockCode != null) ...[
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.warning.withOpacity(0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.warning.withOpacity(0.3)),
          ),
          child: Row(children: [
            const Icon(Icons.info_outline, size: 14, color: AppColors.warning),
            const SizedBox(width: 6),
            Text('Dev mode — OTP: $mockCode',
                style: const TextStyle(color: AppColors.warning, fontSize: 12)),
          ]),
        ),
      ],
    ]);
  }
}

// ── Role-specific fields ──────────────────────────────────────────────────────

class _RoleFields extends StatelessWidget {
  const _RoleFields({
    required this.role,
    required this.licenseCtrl,
    required this.orgCtrl,
    required this.companyCtrl,
    required this.vehicleType,
    required this.selectedHubPin,
    required this.onVehicleChanged,
    required this.onHubChanged,
  });
  final String role;
  final TextEditingController licenseCtrl;
  final TextEditingController orgCtrl;
  final TextEditingController companyCtrl;
  final String? vehicleType;
  final String? selectedHubPin;
  final ValueChanged<String?> onVehicleChanged;
  final ValueChanged<String?> onHubChanged;

  @override
  Widget build(BuildContext context) {
    if (role == 'driver') {
      return Column(children: [
        _Field(
          ctrl: licenseCtrl,
          label: 'Vehicle Registration Number',
          hint: 'OD 02 AB 1234',
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Vehicle number required';
            final fmt = RegExp(r'^[A-Z]{2}\s?\d{2}\s?[A-Z]{1,2}\s?\d{4}$');
            if (!fmt.hasMatch(v.trim().toUpperCase())) {
              return 'Format: MH 01 AB 1234';
            }
            return null;
          },
        ),
        const SizedBox(height: 14),
        _DropdownField<String>(
          label: 'Vehicle Type',
          hint: 'Select vehicle type',
          value: vehicleType,
          items: _vehicleTypes.entries
              .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
              .toList(),
          onChanged: onVehicleChanged,
          validator: (v) => v == null ? 'Vehicle type required' : null,
        ),
        const SizedBox(height: 14),
      ]);
    }

    if (role == 'gatekeeper') {
      return Column(children: [
        _Field(
          ctrl: companyCtrl,
          label: 'Company / Organization Name',
          hint: 'e.g. BlueDart, DTDC, FedEx India',
          validator: (v) =>
              (v?.trim().isEmpty ?? true) ? 'Company name required' : null,
        ),
        const SizedBox(height: 14),
        _DropdownField<String>(
          label: 'Assigned Hub (Odisha Pincode)',
          hint: 'Select distribution hub',
          value: selectedHubPin,
          items: _odishaHubs.entries
              .map((e) => DropdownMenuItem(
                    value: e.key,
                    child: Text('${e.key} – ${e.value}',
                        style: const TextStyle(fontSize: 13)),
                  ))
              .toList(),
          onChanged: onHubChanged,
          validator: (v) => v == null ? 'Hub assignment required' : null,
        ),
        const SizedBox(height: 14),
      ]);
    }

    if (role == 'manager') {
      return Column(children: [
        _Field(
          ctrl: orgCtrl,
          label: 'Organization Name',
          hint: 'Acme Logistics Pvt. Ltd.',
          validator: (v) =>
              (v?.trim().isEmpty ?? true) ? 'Organization name required' : null,
        ),
        const SizedBox(height: 14),
      ]);
    }

    return const SizedBox.shrink();
  }
}

// ── Reusable input widgets ────────────────────────────────────────────────────

InputDecoration _inputDecoration(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textMuted),
      filled: true,
      fillColor: AppColors.cardBg,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.error)),
      focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );

class _Field extends StatelessWidget {
  const _Field({
    required this.ctrl,
    required this.label,
    required this.hint,
    this.keyboardType,
    this.obscureText = false,
    this.validator,
  });
  final TextEditingController ctrl;
  final String label;
  final String hint;
  final TextInputType? keyboardType;
  final bool obscureText;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500)),
      const SizedBox(height: 6),
      TextFormField(
        controller: ctrl,
        keyboardType: keyboardType,
        obscureText: obscureText,
        style: const TextStyle(color: AppColors.textPrimary),
        decoration: _inputDecoration(hint),
        validator: validator,
      ),
    ]);
  }
}

class _DropdownField<T> extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.hint,
    required this.value,
    required this.items,
    required this.onChanged,
    this.validator,
  });
  final String label;
  final String hint;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String? Function(T?)? validator;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500)),
      const SizedBox(height: 6),
      DropdownButtonFormField<T>(
        initialValue: value,
        items: items,
        onChanged: onChanged,
        validator: validator,
        dropdownColor: AppColors.cardBg,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
        decoration: _inputDecoration(hint),
      ),
    ]);
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withOpacity(0.3)),
      ),
      child: Text(message,
          style: const TextStyle(color: AppColors.error, fontSize: 13)),
    );
  }
}
