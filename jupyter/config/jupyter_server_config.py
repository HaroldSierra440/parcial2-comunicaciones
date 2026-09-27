c = get_config()  # noqa: F821

c.ServerApp.ip = "0.0.0.0"
c.ServerApp.port = 8888
c.ServerApp.open_browser = False

c.ServerApp.base_url = "/jupyter"
c.ServerApp.default_url = "/lab/tree/work/analisis_datos.ipynb"
c.LabApp.default_url = "/lab/tree/work/analisis_datos.ipynb"

c.ServerApp.trust_xheaders = True
c.ServerApp.allow_remote_access = True
c.ServerApp.allow_origin = "*"

c.ServerApp.token = ""
c.ServerApp.password = ""
c.IdentityProvider.token = ""
c.PasswordIdentityProvider.hashed_password = ""
c.PasswordIdentityProvider.password_required = False

c.ServerApp.root_dir = "/home/jovyan"
c.ServerApp.shutdown_no_activity_timeout = 0
c.MappingKernelManager.cull_idle_timeout = 0