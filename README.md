# 🔐 Secure Vault

A simple, secure, and user-friendly command-line vault for storing sensitive data using password-based encryption with [`age`](https://github.com/FiloSottile/age). Works on **Ubuntu/Linux**.

---

## ✨ Features

- Encrypt key-value secrets or entire files
- Decrypt secrets to file or view in terminal
- Store secrets in a safe vault folder
- Use your own memorable password — no key files needed
- Interactive CLI with built-in editor and validation

---

## 🛠 Requirements

- [age](https://github.com/FiloSottile/age) (encryption tool)

Install `age`:

```bash
sudo apt update
sudo apt install age -y
