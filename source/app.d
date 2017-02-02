import vibe.d;
import vibe.db.postgresql;
import dpq2;

import std.datetime;
import std.stdio;
import std.conv;

immutable connectionUri = "postgresql://root:root@localhost:5432/board";

shared PostgresClient client;

shared static this()
{
	client = new shared PostgresClient(connectionUri, 4);

	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	settings.bindAddresses = ["::1", "127.0.0.1"];

	auto router = new URLRouter;
	router.get("/", (req, res) => res.redirect("/posts"));
	router.get("/posts", &indexPosts);
	router.post("/posts", &createPost);
	router.get("/posts/:id/delete", &deletePost);
	router.get("*", serveStaticFiles("./public/"));

	listenHTTP(settings, router);

	logInfo("Please open http://127.0.0.1:8080/ in your browser.");
}

struct Post
{
	long id;
    string title;
	string author;
	string text;
	DateTime postedAt;

	string printPostedTime() @property pure
	{
		import std.format;
		with (postedAt) return
			format("%04d-%02d-%02d %02d:%02d:%02d", year, cast(int)month, day, hour, minute, second);
	}

	unittest
	{
		assert(Post(0, "", "", "", DateTime(2016, 12, 24)).printPostedTime == "2016-12-24 00:00:00");
		assert(Post(0, "", "", "", DateTime(2016, 12, 24, 23, 0, 0)).printPostedTime == "2016-12-24 23:00:00");
	}
}

void indexPosts(HTTPServerRequest req, HTTPServerResponse res)
{
	auto conn = client.lockConnection();
	scope (exit) destroy(conn);

	Post[] posts;
	auto rs = conn.execStatement("SELECT id, title, author, text, posted_at FROM posts ORDER BY id DESC", ValueFormat.BINARY);
	for (size_t i = 0; i < rs.length; ++i) {
		auto r = rs[i];
		posts ~= Post(
			r["id"].as!PGbigint,
			r["title"].as!PGtext,
			r["author"].as!PGtext,
			r["text"].as!PGtext,
			r["posted_at"].as!PGtimestamp_without_time_zone.dateTime
		);
	}

	res.render!("index.dt", posts);
}

void createPost(HTTPServerRequest req, HTTPServerResponse res)
{
	auto conn = client.lockConnection();
	scope (exit) destroy(conn);

	immutable title = req.form["title"];
	immutable author = req.form["author"];
	immutable text = req.form["text"];

	if (title != "" && author != "" && text != "") {
		QueryParams qps;
		qps.sqlCommand = "INSERT INTO posts VALUES ((SELECT COUNT(*) FROM posts) + 1, $1, $2, $3, now())";
		qps.argsFromArray = [title, author, text];
		conn.execParams(qps);
	}

	res.redirect("/");
}

void deletePost(HTTPServerRequest req, HTTPServerResponse res)
{
	auto conn = client.lockConnection();
	scope (exit) destroy(conn);

	enforceHTTP("id" in req.params, HTTPStatus.badRequest, "Query string must have key of 'id'.");

	auto postId = req.params["id"];

	QueryParams qps;
	qps.sqlCommand = "DELETE FROM posts WHERE id = $1::bigint";
	qps.argsFromArray = [postId];
	conn.execParams(qps);

	res.redirect("/");
}