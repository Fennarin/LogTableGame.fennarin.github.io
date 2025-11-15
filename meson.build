project('LogTableGame', 'vala', 'c')

dependencies = [
	dependency('glib-2.0'),
	dependency('gtk4'),
	meson.get_compiler('c').find_library('m')
]

sources = []
subdir('src')

gnome = import('gnome')

gresource = gnome.compile_resources(
    'gresource',
    'data' / 'gresource.xml',
    source_dir: 'data'
)

executable(
	meson.project_name(),
	gresource,
	sources,
	dependencies: dependencies,
	install: true
)

