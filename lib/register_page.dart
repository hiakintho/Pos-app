import 'package:flutter/material.dart';
import 'app_loading_indicator.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'main.dart';
import 'models.dart';
import 'account_security.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String _selectedRole = UserRole.cashier;
  String? _selectedBranch;
  bool _isLoading = false;
  List<RolePermissions> _availableRoles = [];
  List<Branch> _availableBranches = [];
  List<Map<String, dynamic>> _systemFeatures = [];

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
  }

  Future<void> _fetchInitialData() async {
    final rolesSnapshot = await FirebaseFirestore.instance
        .collection('roles')
        .get();
    final featuresSnapshot = await FirebaseFirestore.instance
        .collection('features')
        .get();
    final branchesSnapshot = await FirebaseFirestore.instance
        .collection('branches')
        .get();

    setState(() {
      _availableRoles = rolesSnapshot.docs
          .map((doc) => RolePermissions.fromMap(doc.data()))
          .toList();
      _systemFeatures = featuresSnapshot.docs
          .map((doc) => {'id': doc.id, ...doc.data()})
          .toList();
      _availableBranches = branchesSnapshot.docs
          .map((doc) => Branch.fromMap(doc.data()))
          .toList();

      if (_availableRoles.any((r) => r.roleId == UserRole.cashier)) {
        _selectedRole = UserRole.cashier;
      } else if (_availableRoles.isNotEmpty) {
        _selectedRole = _availableRoles.first.roleId;
      }
    });
  }

  Future<void> _register() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }
    final passwordError = strongPasswordError(password);
    if (passwordError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(passwordError)));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final auth.UserCredential userCredential = await auth
          .FirebaseAuth
          .instance
          .createUserWithEmailAndPassword(email: email, password: password);

      final newUser = User(
        id: userCredential.user!.uid,
        name: name,
        email: email,
        role: _selectedRole,
        branchId: _selectedBranch,
      );

      await FirebaseFirestore.instance
          .collection('users')
          .doc(newUser.id)
          .set(newUser.toMap());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Registration successful.')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const RubenLogo(fontSize: 24),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
        child: Column(
          children: [
            const Text(
              'Create Account',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 30),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                hintText: 'Full Name',
                filled: true,
                fillColor: Colors.grey[900],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(5),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _emailController,
              decoration: InputDecoration(
                hintText: 'Email',
                filled: true,
                fillColor: Colors.grey[900],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(5),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: InputDecoration(
                hintText: 'Strong password (10+ characters)',
                helperText: 'Uppercase, lowercase, number, and symbol required',
                filled: true,
                fillColor: Colors.grey[900],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(5),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 15),
            DropdownButtonFormField<String?>(
              initialValue: _selectedBranch,
              dropdownColor: Colors.grey[900],
              decoration: InputDecoration(
                labelText: 'Assign to Branch',
                filled: true,
                fillColor: Colors.grey[900],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(5),
                  borderSide: BorderSide.none,
                ),
              ),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('No Specific Branch'),
                ),
                ..._availableBranches.map((branch) {
                  return DropdownMenuItem(
                    value: branch.id,
                    child: Text(branch.name),
                  );
                }),
              ],
              onChanged: (val) => setState(() => _selectedBranch = val),
            ),
            const SizedBox(height: 15),
            _availableRoles.isEmpty
                ? const ModernLoadingIndicator()
                : DropdownButtonFormField<String>(
                    initialValue: _selectedRole,
                    dropdownColor: Colors.grey[900],
                    decoration: InputDecoration(
                      labelText: 'Select Role',
                      filled: true,
                      fillColor: Colors.grey[900],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(5),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    items: _availableRoles.map((role) {
                      return DropdownMenuItem(
                        value: role.roleId,
                        child: Text(role.displayName),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedRole = val);
                    },
                  ),
            if (_availableRoles.isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 15),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.indigo.withOpacity(0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Role Access Summary:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.indigoAccent,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...(_availableRoles
                        .firstWhere(
                          (r) => r.roleId == _selectedRole,
                          orElse: () => _availableRoles.first,
                        )
                        .permissions
                        .entries
                        .map(
                          (e) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                Icon(
                                  e.value
                                      ? Icons.check_circle
                                      : Icons.cancel_outlined,
                                  color: e.value ? Colors.green : Colors.grey,
                                  size: 16,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  e.key,
                                  style: TextStyle(
                                    color: e.value ? Colors.white : Colors.grey,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )),
                  ],
                ),
              ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _register,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
                child: _isLoading
                    ? const ModernLoadingIndicator(color: Colors.white)
                    : const Text(
                        'Register',
                        style: TextStyle(color: Colors.white),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
