import os
import re
import time
import requests

BASE = os.environ.get("JOOMLA_URL", "http://joomla")
USER = os.environ["JOOMLA_ADMIN_USERNAME"]
PASS = os.environ["JOOMLA_ADMIN_PASSWORD"]

session = requests.Session()


def get_token(html):
    m = re.search(r'name="([0-9a-f]{32})" value="1"', html)
    if not m:
        raise RuntimeError("No se encontro el token CSRF en la pagina")
    return m.group(1)


def wait_joomla():
    for intento in range(30):
        try:
            r = session.get(BASE + "/administrator/index.php", timeout=5)
            if r.status_code == 200:
                return r.text
        except requests.RequestException:
            pass
        print("Esperando a que Joomla responda... intento", intento + 1)
        time.sleep(3)
    raise RuntimeError("Joomla no respondio a tiempo")


def login():
    html = wait_joomla()
    token = get_token(html)
    print("Token CSRF encontrado:", token)

    data = {
        "username": USER,
        "passwd": PASS,
        "option": "com_login",
        "task": "login",
        "return": "",
        token: "1",
    }
    r1 = session.post(BASE + "/administrator/index.php", data=data, timeout=10, allow_redirects=True)
    print("Status del POST de login:", r1.status_code)
    print("URL final tras el login:", r1.url)

    r2 = session.get(BASE + "/administrator/index.php?option=com_cpanel", timeout=10)
    print("Status al pedir el panel:", r2.status_code)
    print("URL final al pedir el panel:", r2.url)
    print("Contiene 'com_login' (senal de que NO quedo logueado):", "option=com_login" in r2.url)
    print("Primeros 500 caracteres de la respuesta:")
    print(r2.text[:500])

    if "option=com_login" in r2.url:
        raise RuntimeError("No se pudo iniciar sesion en Joomla")
    print("Login en Joomla exitoso.")


def article_exists():
    r = session.get(
        BASE + "/administrator/index.php?option=com_content&view=articles",
        timeout=10,
    )
    return "Bienvenida al Portal" in r.text


def create_article():
    r = session.get(
        BASE + "/administrator/index.php?option=com_content&task=article.add",
        timeout=10,
    )
    token = get_token(r.text)
    cuerpo = (
        '<p><img src="/images/custom/bienvenida.png" alt="Bienvenida" '
        'style="max-width:100%;height:auto;" /></p>'
    )
    data = {
        "jform[title]": "Bienvenida al Portal",
        "jform[catid]": "2",
        "jform[articletext]": cuerpo,
        "jform[state]": "1",
        "jform[featured]": "1",
        "jform[language]": "*",
        "jform[access]": "1",
        "task": "article.save",
        "option": "com_content",
        token: "1",
    }
    r2 = session.post(
        BASE + "/administrator/index.php?option=com_content&task=article.save",
        data=data,
        timeout=10,
    )
    print("Respuesta al guardar articulo:", r2.status_code)


login()
if article_exists():
    print("El articulo de bienvenida ya existe, no se crea de nuevo.")
else:
    create_article()
    print("Articulo de bienvenida creado y marcado como Featured.")