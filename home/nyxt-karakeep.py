"""Small stdin/stdout JSON bridge for Nyxt; credentials never enter Lisp or argv."""

import json
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

ORIGIN = "https://horde.nogroup.group"
VAULT_ENTRY = "Karakeep Nyxt API"


class IntegrationError(Exception):
    pass


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise IntegrationError("Karakeep redirected the API request; check its server configuration.")


def api_token():
    result = subprocess.run(
        ["rbw", "get", "--", VAULT_ENTRY], capture_output=True, text=True, timeout=90
    )
    if result.returncode:
        raise IntegrationError("Cannot read Karakeep Nyxt API from Vaultwarden. Run rbw unlock and rbw sync.")
    token = result.stdout.removesuffix("\n")
    if not token or any(c.isspace() for c in token):
        raise IntegrationError("The Karakeep API credential is empty or invalid.")
    return token


class Client:
    def __init__(self, token):
        self.token = token
        self.opener = urllib.request.build_opener(NoRedirect())

    def request(self, path, data=None, *, method=None):
        request = urllib.request.Request(
            ORIGIN + "/api/v1" + path,
            data=json.dumps(data).encode() if data is not None else None,
            method=method,
            headers={"Authorization": "Bearer " + self.token,
                     "Content-Type": "application/json", "Accept": "application/json"},
        )
        try:
            with self.opener.open(request, timeout=25) as response:
                return None if response.status == 204 else json.load(response)
        except urllib.error.HTTPError as error:
            if error.code in (401, 403):
                raise IntegrationError("Karakeep rejected the API credential or its permissions.") from None
            raise IntegrationError(f"Karakeep API returned HTTP {error.code}.") from None
        except (urllib.error.URLError, TimeoutError):
            raise IntegrationError("Cannot reach Karakeep over HTTPS. Check the service and network.") from None


def web_url(value):
    if not isinstance(value, str):
        raise IntegrationError("Select an HTTP(S) page or link to save.")
    parsed = urllib.parse.urlsplit(value)
    if (parsed.scheme not in ("http", "https") or not parsed.hostname
            or parsed.username is not None or parsed.password is not None
            or any(c in value for c in "\r\n\t")):
        raise IntegrationError("Only HTTP(S) URLs without embedded credentials can be saved.")
    return value


def bookmark_result(bookmark):
    content = bookmark.get("content") or {}
    identifier = urllib.parse.quote(bookmark["id"], safe="")
    url = content.get("url") or content.get("sourceUrl") or ""
    # Remote data must never turn a prompt selection into javascript/file navigation.
    try:
        url = web_url(url)
    except IntegrationError:
        url = ""
    return {"id": bookmark["id"],
            "title": bookmark.get("title") or content.get("title") or url or "Untitled",
            "url": url,
            "reader": ORIGIN + "/reader/" + identifier,
            "tags": [tag["name"] for tag in bookmark.get("tags", [])]}


def writable_lists(client):
    lists = client.request("/lists")["lists"]
    by_id = {item["id"]: item for item in lists}
    result = []
    for item in lists:
        if item.get("type", "manual") != "manual" or item.get("userRole") not in ("owner", "editor"):
            continue
        names, seen = [item["name"]], {item["id"]}
        parent = item.get("parentId")
        while parent in by_id and parent not in seen:
            seen.add(parent)
            names.insert(0, by_id[parent]["name"])
            parent = by_id[parent].get("parentId")
        result.append({"id": item["id"], "name": item["name"], "path": " / ".join(names)})
    return sorted(result, key=lambda item: (item["path"].casefold(), item["id"]))


def execute(data, client):
    action = data["action"]
    if action == "lists":
        return {"lists": writable_lists(client)}
    if action == "save":
        url = web_url(data.get("url"))
        selected_list = None
        if data.get("listId"):
            selected_list = next((item for item in writable_lists(client)
                                  if item["id"] == data["listId"]), None)
            if selected_list is None:
                raise IntegrationError("That list is no longer writable. Nothing saved; choose another list.")
        bookmark = client.request("/bookmarks", {"type": "link", "url": url,
                                  "title": (data.get("title") or "")[:1000] or None,
                                  "source": "api"})
        result = bookmark_result(bookmark)
        warnings = []
        tags = list(dict.fromkeys(t.strip() for t in data.get("tags", []) if t.strip()))
        if tags:
            try:
                client.request("/bookmarks/" + urllib.parse.quote(result["id"], safe="") + "/tags",
                               {"tags": [{"tagName": tag} for tag in tags]})
            except IntegrationError:
                warnings.append("Bookmark saved, but tags failed. Save again to retry adding tags.")
        if selected_list:
            try:
                client.request("/lists/" + urllib.parse.quote(selected_list["id"], safe="")
                               + "/bookmarks/" + urllib.parse.quote(result["id"], safe=""), method="PUT")
                result["list"] = selected_list["path"]
            except IntegrationError:
                warnings.append("Bookmark saved, but adding it to the list failed. Save again to retry.")
        if warnings:
            result["warning"] = " ".join(warnings)
        return result
    if action == "search":
        query = data.get("query", "").strip()
        path = "/bookmarks/search" if query else "/bookmarks"
        params = {"limit": 100, "includeContent": "false"}
        if query:
            params["q"] = query
        response = client.request(path + "?" + urllib.parse.urlencode(params))
        return {"bookmarks": [bookmark_result(b) for b in response["bookmarks"]],
                "more": bool(response.get("nextCursor"))}
    raise IntegrationError("Unknown Karakeep operation.")


def main():
    try:
        data = json.load(sys.stdin)
        # Reject unsupported requests before accessing the vault.
        if data.get("action") not in ("save", "search", "lists"):
            raise IntegrationError("Unknown Karakeep operation.")
        if data["action"] == "save":
            web_url(data.get("url"))
        result = execute(data, Client(api_token()))
        print(json.dumps({"ok": True, "result": result}))
    except IntegrationError as error:
        print(json.dumps({"ok": False, "error": str(error)}))
        return 1
    except Exception:
        # Never include subprocess output, HTTP bodies, headers or tracebacks.
        print(json.dumps({"ok": False, "error": "Karakeep integration failed; check the service and Vaultwarden."}))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
