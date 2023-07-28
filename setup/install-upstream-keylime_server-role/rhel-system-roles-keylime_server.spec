Name:		rhel-system-roles-keylime_server
Version:	99
Release:	1
Summary:	Dummy package preventing rhel-system-roles RPM installation
License:	GPLv2+	
BuildArch:  noarch
Provides: rhel-system-roles

%description
Dummy package that prevents replacing installed rhel-system-roles bits with custom RPM

%prep

%build

%install

%preun
rm -rf /usr/share/ansible/roles/rhel-system-roles.keylime_server

%files

%changelog
* Fri Jul 28 2022 Karel Srot <ksrot@redhat.com> 99-1
- Initial version
