# Contributing to Photos for NAS Synology

Thank you for your interest in contributing to **Photos for NAS Synology**! This is an open-source community project developed for Ubuntu Touch (Lomiri).

## Bug Reports and Feature Requests

Please use the issue tracker to report bugs or suggest new features. Provide as much context as possible:

- Device model and Ubuntu Touch version (e.g., Focal 20.04).
- Synology DSM and Synology Photos version.
- Steps to reproduce the issue.
- Log output or screenshots if applicable.

## Pull Requests

1. Fork the repository.
2. Create a new branch for your feature or bugfix.
3. Commit your changes with clear messages (e.g., `feat: add album browser view`, `fix: handle 2FA login errors`).
4. Submit a Pull Request against the main branch.

## Setting Up the Development Environment

The project uses [Clickable](https://clickable-ut.dev/) for building, testing, and packaging for Ubuntu Touch.

1. **Install Clickable:**
   ```bash
   pip3 install --user clickable-ut
   # or via snap
   sudo snap install clickable --classic
   ```

2. **Clone the Repository:**
   ```bash
   git clone https://github.com/puqcloud/Photos-for-NAS-Synology.git
   cd Photos-for-NAS-Synology
   ```

3. **Run on Desktop (Simulator):**
   ```bash
   clickable desktop
   ```

4. **Build and Deploy to Device:**
   Connect your Ubuntu Touch device via USB with Developer Mode enabled:
   ```bash
   clickable
   ```

## Code Guidelines

- **QML / JavaScript:** Follow standard Qt Quick best practices and Ubuntu UI Toolkit (Lomiri) guidelines.
- **UI & UX:** Maintain responsive design that works seamlessly on both mobile screens and convergence / desktop displays.
- **Privacy & Security:** Do not hardcode any credentials, tokens, or personal server addresses. All sensitive data must remain strictly on the user's local device storage.

## Legal Notice

All contributions will be licensed under the [MIT License](LICENSE).
Please note that "Synology" and "Synology Photos" are trademarks of Synology Inc. This project is an unofficial community effort.
