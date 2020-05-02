--
-- PostgreSQL database dump
--

-- Dumped from database version 12.2 (Debian 12.2-2.pgdg100+1)
-- Dumped by pg_dump version 12.2 (Debian 12.2-2.pgdg100+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: after_delete_blacklist(); Type: FUNCTION; Schema: public; Owner: nerdz
--

CREATE FUNCTION public.after_delete_blacklist() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

    BEGIN

        DELETE FROM "posts_no_notify" WHERE "user" = OLD."to" AND (
            "hpid" IN (

                SELECT "hpid"  FROM "posts" WHERE "from" = OLD."to" AND "to" = OLD."from"

                ) OR "hpid" IN (

                SELECT "hpid"  FROM "comments" WHERE "from" = OLD."to" AND "to" = OLD."from"

            )
        );

        RETURN OLD;

END

$$;


ALTER FUNCTION public.after_delete_blacklist() OWNER TO nerdz;

--
-- Name: after_delete_user(); Type: FUNCTION; Schema: public; Owner: nerdz
--

CREATE FUNCTION public.after_delete_user() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
    insert into deleted_users(counter, username) values(OLD.counter, OLD.username);
    RETURN NULL;
    -- if the user gives a motivation, the upper level might update this row
end $$;


ALTER FUNCTION public.after_delete_user() OWNER TO nerdz;

--
-- Name: after_insert_blacklist(); Type: FUNCTION; Schema: public; Owner: nerdz
--

CREATE FUNCTION public.after_insert_blacklist() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE r RECORD;
BEGIN
    INSERT INTO posts_no_notify("user","hpid")
    (
        SELECT NEW."from", "hpid" FROM "posts" WHERE "to" = NEW."to" OR "from" = NEW."to" -- posts made by the blacklisted user and post on his board
        UNION DISTINCT
        SELECT NEW."from", "hpid" FROM "comments" WHERE "from" = NEW."to" OR "to" = NEW."to" -- comments made by blacklisted user on others and his board
    )
    EXCEPT -- except existing ones
    (
        SELECT NEW."from", "hpid" FROM "posts_no_notify" WHERE "user" = NEW."from"
    );

    INSERT INTO groups_posts_no_notify("user","hpid")
    (
        (
            SELECT NEW."from", "hpid" FROM "groups_posts" WHERE "from" = NEW."to" -- posts made by the blacklisted user in every project
            UNION DISTINCT
            SELECT NEW."from", "hpid" FROM "groups_comments" WHERE "from" = NEW."to" -- comments made by the blacklisted user in every project
        )
        EXCEPT -- except existing ones
        (
            SELECT NEW."from", "hpid" FROM "groups_posts_no_notify" WHERE "user" = NEW."from"
        )
    );


    FOR r IN (SELECT "to" FROM "groups_owners" WHERE "from" = NEW."from")
        LOOP
            -- remove from my groups members
            DELETE FROM "groups_members" WHERE "from" = NEW."to" AND "to" = r."to";
END LOOP;

-- remove from followers
DELETE FROM "followers" WHERE ("from" = NEW."from" AND "to" = NEW."to");

-- remove pms
DELETE FROM "pms" WHERE ("from" = NEW."from" AND "to" = NEW."to") OR ("to" = NEW."from" AND "from" = NEW."to");

-- remove from mentions
DELETE FROM "mentions" WHERE ("from"= NEW."from" AND "to" = NEW."to") OR ("to" = NEW."from" AND "from" = NEW."to");

RETURN NULL;
END $$;


ALTER FUNCTION public.after_insert_blacklist() OWNER TO nerdz;

--
-- Name: after_insert_group_post(); Type: FUNCTION; Schema: public; Owner: nerdz
--

CREATE FUNCTION public.after_insert_group_post() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    WITH to_notify("user") AS (
        (
            -- members
            SELECT "from" FROM "groups_members" WHERE "to" = NEW."to"
            UNION DISTINCT
            --followers
            SELECT "from" FROM "groups_followers" WHERE "to" = NEW."to"
            UNION DISTINCT
            SELECT "from"  FROM "groups_owners" WHERE "to" = NEW."to"
        )
        EXCEPT
        (
            -- blacklist
            SELECT "from" AS "user" FROM "blacklist" WHERE "to" = NEW."from"
            UNION DISTINCT
            SELECT "to" AS "user" FROM "blacklist" WHERE "from" = NEW."from"
            UNION DISTINCT
            SELECT NEW."from" -- I shouldn't be notified about my new post
        )
    )

    INSERT INTO "groups_notify"("from", "to", "time", "hpid") (
        SELECT NEW."to", "user", NEW."time", NEW."hpid" FROM to_notify
    );

    PERFORM hashtag(NEW.message, NEW.hpid, true, NEW.from, NEW.time);
    PERFORM mention(NEW."from", NEW.message, NEW.hpid, true);
    RETURN NULL;
 END $$;


ALTER FUNCTION public.after_insert_group_post() OWNER TO nerdz;

--
-- Name: after_insert_user(); Type: FUNCTION; Schema: public; Owner: nerdz
--

CREATE FUNCTION public.after_insert_user() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO "profiles"(counter) VALUES(NEW.counter);
    RETURN NULL;
END $$;


ALTER FUNCTION public.after_insert_user() OWNER TO nerdz;

--
-- Name: after_insert_user_post(); Type: FUNCTION; Schema: public; Owner: nerdz
--

CREATE FUNCTION public.after_insert_user_post() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
    IF NEW."from" <> NEW."to" THEN
        insert into posts_notify("from", "to", "hpid", "time") values(NEW."from", NEW."to", NEW."hpid", NEW."time");
END IF;
PERFORM hashtag(NEW.message, NEW.hpid, false, NEW.from, NEW.time);
PERFORM mention(NEW."from", NEW.message, NEW.hpid, false);
return null;
end $$;


ALTER FUNCTION public.after_insert_user_post() OWNER TO nerdz;

--
-- Name: after_update_userame(); Type: FUNCTION; Schema: public; Owner: nerdz
--

CREATE FUNCTION public.after_update_userame() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- create news
    insert into posts("from","to","message")
    SELECT counter, counter,
    OLD.username || ' %%12now is34%% [user]' || NEW.username || '[/user]' FROM special_users WHERE "role" = 'GLOBAL_NEWS';

    RETURN NULL;
END $$;


ALTER FUNCTION public.after_update_userame() OWNER TO nerdz;

--
-- Name: before_delete_user(); Type: FUNCTION; Schema: public; Owner: nerdz
--

CREATE FUNCTION public.before_delete_user() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE "comments" SET "from" = (SELECT "counter" FROM "special_users" WHERE "role" = 'DELETED') WHERE "from" = OLD.counter;
    UPDATE "posts" SET "from" = (SELECT "counter" FROM "special_users" WHERE "role" = 'DELETED') WHERE "from" = OLD.counter;

    UPDATE "groups_comments" SET "from" = (SELECT "counter" FROM "special_users" WHERE "role" = 'DELETED') WHERE "from" = OLD.counter;            
    UPDATE "groups_posts" SET "from" = (SELECT "counter" FROM "special_users" WHERE "role" = 'DELETED') WHERE "from" = OLD.counter;

    PERFORM handle_groups_on_user_delete(OLD.counter);

    RETURN OLD;
END
$$;


ALTER FUNCTION public.before_delete_user() OWNER TO nerdz;

--
-- Name: before_insert_comment(); Type: FUNCTION; Schema: public; Owner: nerdz
--

CREATE FUNCTION public.before_insert_comment() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE closedPost boolean;
BEGIN
    PERFORM flood_control('"comments"', NEW."from", NEW.message);
    SELECT closed FROM posts INTO closedPost WHERE hpid = NEW.hpid;
    IF closedPost THEN
        RAISE EXCEPTION 'CLOSED_POST';
END IF;

SELECT p."to" INTO NEW."to" FROM "posts" p WHERE p.hpid = NEW.hpid;
PERFORM blacklist_control(NEW."from", NEW."to");

NEW.message = message_control(NEW.message);

RETURN NEW;
END $$;


ALTER FUNCTION public.before_insert_comment() OWNER TO nerdz;

--
-- Name: before_insert_comment_thumb(); Type: FUNCTION; Schema: public; Owner: nerdz
--

CREATE FUNCTION public.before_insert_comment_thumb() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE postFrom int8;
tmp record;
BEGIN
    PERFORM flood_control('"comment_thumbs"', NEW."from");

    SELECT T."to", T."from", T."hpid" INTO tmp FROM (SELECT "from", "to", "hpid" FROM "comments" WHERE "hcid" = NEW.hcid) AS T;
    SELECT tmp."from" INTO NEW."to";

    PERFORM blacklist_control(NEW."from", NEW."to"); --blacklisted commenter

    SELECT T."from", T."to" INTO tmp FROM (SELECT p."from", p."to" FROM "posts" p WHERE p.hpid = tmp.hpid) AS T;

    PERFORM blacklist_control(NEW."from", tmp."from"); --blacklisted post creator
    IF tmp."from" <> tmp."to" THEN
        PERFORM blacklist_control(NEW."from", tmp."to"); --blacklisted post destination user
END IF;

IF NEW."vote" = 0 THEN
    DELETE FROM "comment_thumbs" WHERE hcid = NEW.hcid AND "from" = NEW."from";
    RETURN NULL;
END IF;

WITH new_values (hcid, "from", vote) AS (
    VALUES(NEW."hcid", NEW."from", NEW."vote")
),
upsert AS (
    UPDATE "comment_thumbs" AS m
    SET vote = nv.vote
    FROM new_values AS nv
    WHERE m.hcid = nv.hcid AND m."from" = nv."from"
    RETURNING m.*
)

SELECT "vote" INTO NEW."vote"
FROM new_values
WHERE NOT EXISTS (
    SELECT 1
    FROM upsert AS up
    WHERE up.hcid = new_values.hcid AND up."from" = new_values."from"
);

IF NEW."vote" IS NULL THEN -- updated previous vote
    RETURN NULL; --no need to insert new value
END IF;

RETURN NEW;
END $$;


ALTER FUNCTION public.before_insert_comment_thumb() OWNER TO nerdz;

--
-- Name: before_insert_follower(); Type: FUNCTION; Schema: public; Owner: nerdz
--

CREATE FUNCTION public.before_insert_follower() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM flood_control('"followers"', NEW."from");
    IF NEW."from" = NEW."to" THEN
        RAISE EXCEPTION 'CANT_FOLLOW_YOURSELF';
END IF;
PERFORM blacklist_control(NEW."from", NEW."to");
RETURN NEW;
END $$;


ALTER FUNCTION public.before_insert_follower() OWNER TO nerdz;

--
-- Name: before_insert_group_post_lurker(); Type: FUNCTION; Schema: public; Owner: nerdz
--

CREATE FUNCTION public.before_insert_group_post_lurker() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE tmp RECORD;
BEGIN
    PERFORM flood_control('"groups_lurkers"', NEW."from");

    SELECT T."to", T."from" INTO tmp FROM (SELECT "to", "from" FROM "groups_posts" WHERE "hpid" = NEW.hpid) AS T;

    SELECT tmp."to" INTO NEW."to";

    PERFORM blacklist_control(NEW."from", tmp."from"); --blacklisted post creator

    IF NEW."from" IN ( SELECT "from" FROM "groups_comments" WHERE hpid = NEW.hpid ) THEN
        RAISE EXCEPTION 'CANT_LURK_IF_POSTED';
END IF;

RETURN NEW;
END $$;


ALTER FUNCTION public.before_insert_group_post_lurker() OWNER TO nerdz;

--
-- Name: before_insert_groups_comment(); Type: FUNCTION; Schema: public; Owner: nerdz
--

CREATE FUNCTION public.before_insert_groups_comment() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE postFrom int8;
closedPost boolean;
BEGIN
    PERFORM flood_control('"groups_comments"', NEW."from", NEW.message);

    SELECT closed FROM groups_posts INTO closedPost WHERE hpid = NEW.hpid;
    IF closedPost THEN
        RAISE EXCEPTION 'CLOSED_POST';
END IF;

SELECT p."to" INTO NEW."to" FROM "groups_posts" p WHERE p.hpid = NEW.hpid;

NEW.message = message_control(NEW.message);


SELECT T."from" INTO postFrom FROM (SELECT "from" FROM "groups_posts" WHERE hpid = NEW.hpid) AS T;
PERFORM blacklist_control(NEW."from", postFrom); --blacklisted post creator

RETURN NEW;
END $$;


ALTER FUNCTION public.before_insert_groups_comment() OWNER TO nerdz;

--
-- Name: before_insert_groups_comment_thumb(); Type: FUNCTION; Schema: public; Owner: nerdz
--

CREATE FUNCTION public.before_insert_groups_comment_thumb() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE tmp record;
postFrom int8;
BEGIN
    PERFORM flood_control('"groups_comment_thumbs"', NEW."from");

    SELECT T."hpid", T."from", T."to" INTO tmp FROM (SELECT "hpid", "from","to" FROM "groups_comments" WHERE "hcid" = NEW.hcid) AS T;
    SELECT tmp."from" INTO NEW."to";

    PERFORM blacklist_control(NEW."from", NEW."to"); --blacklisted commenter

    SELECT T."from" INTO postFrom FROM (SELECT p."from" FROM "groups_posts" p WHERE p.hpid = tmp.hpid) AS T;

    PERFORM blacklist_control(NEW."from", postFrom); --blacklisted post creator

    IF NEW."vote" = 0 THEN
        DELETE FROM "groups_comment_thumbs" WHERE hcid = NEW.hcid AND "from" = NEW."from";
        RETURN NULL;
END IF;

WITH new_values (hcid, "from", vote) AS (
    VALUES(NEW."hcid", NEW."from", NEW."vote")
),
upsert AS (
    UPDATE "groups_comment_thumbs" AS m
    SET vote = nv.vote
    FROM new_values AS nv
    WHERE m.hcid = nv.hcid AND m."from" = nv."from"
    RETURNING m.*
)

SELECT "vote" INTO NEW."vote"
FROM new_values
WHERE NOT EXISTS (
    SELECT 1
    FROM upsert AS up
    WHERE up.hcid = new_values.hcid AND up."from" = new_values."from"
);

IF NEW."vote" IS NULL THEN -- updated previous vote
    RETURN NULL; --no need to insert new value
END IF;

RETURN NEW;
END $$;


ALTER FUNCTION public.before_insert_groups_comment_thumb() OWNER TO nerdz;

--
-- Name: before_insert_groups_follower(); Type: FUNCTION; Schema: public; Owner: nerdz
--

CREATE FUNCTION public.before_insert_groups_follower() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE group_owner int8;
BEGIN
    PERFORM flood_control('"groups_followers"', NEW."from");
    SELECT "from" INTO group_owner FROM "groups_owners" WHERE "to" = NEW."to";
    PERFORM blacklist_control(group_owner, NEW."from");
    RETURN NEW;
END $$;


ALTER FUNCTION public.before_insert_groups_follower() OWNER TO nerdz;

--
-- Name: before_insert_groups_member(); Type: FUNCTION; Schema: public; Owner: nerdz
--

CREATE FUNCTION public.before_insert_groups_member() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE group_owner int8;
BEGIN
    SELECT "from" INTO group_owner FROM "groups_owners" WHERE "to" = NEW."to";
    PERFORM blacklist_control(group_owner, NEW."from");
    RETURN NEW;
END $$;


ALTER FUNCTION public.before_insert_groups_member() OWNER TO nerdz;

--
-- Name: before_insert_groups_thumb(); Type: FUNCTION; Schema: public; Owner: nerdz
--

CREATE FUNCTION public.before_insert_groups_thumb() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE  tmp record;
BEGIN
    PERFORM flood_control('"groups_thumbs"', NEW."from");

    SELECT T."to", T."from" INTO tmp
    FROM (SELECT "to", "from" FROM "groups_posts" WHERE "hpid" = NEW.hpid) AS T;

    SELECT tmp."from" INTO NEW."to";

    PERFORM blacklist_control(NEW."from", NEW."to"); -- blacklisted post creator

    IF NEW."vote" = 0 THEN
        DELETE FROM "groups_thumbs" WHERE hpid = NEW.hpid AND "from" = NEW."from";
        RETURN NULL;
END IF;

WITH new_values (hpid, "from", vote) AS (
    VALUES(NEW."hpid", NEW."from", NEW."vote")
),
upsert AS (
    UPDATE "groups_thumbs" AS m
    SET vote = nv.vote
    FROM new_values AS nv
    WHERE m.hpid = nv.hpid AND m."from" = nv."from"
    RETURNING m.*
)

SELECT "vote" INTO NEW."vote"
FROM new_values
WHERE NOT EXISTS (
    SELECT 1
    FROM upsert AS up
    WHERE up.hpid = new_values.hpid AND up."from" = new_values."from"
);

IF NEW."vote" IS NULL THEN -- updated previous vote
    RETURN NULL; --no need to insert new value
END IF;

RETURN NEW;
END $$;


ALTER FUNCTION public.before_insert_groups_thumb() OWNER TO nerdz;

--
-- Name: before_insert_pm(); Type: FUNCTION; Schema: public; Owner: nerdz
--

CREATE FUNCTION public.before_insert_pm() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE myLastMessage RECORD;
BEGIN
    NEW.message = message_control(NEW.message);
    PERFORM flood_control('"pms"', NEW."from", NEW.message);

    IF NEW."from" = NEW."to" THEN
        RAISE EXCEPTION 'CANT_PM_YOURSELF';
END IF;

PERFORM blacklist_control(NEW."from", NEW."to");
RETURN NEW;
END $$;


ALTER FUNCTION public.before_insert_pm() OWNER TO nerdz;

--
-- Name: before_insert_thumb(); Type: FUNCTION; Schema: public; Owner: nerdz
--

CREATE FUNCTION public.before_insert_thumb() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE tmp RECORD;
BEGIN
    PERFORM flood_control('"thumbs"', NEW."from");

    SELECT T."to", T."from" INTO tmp FROM (SELECT "to", "from" FROM "posts" WHERE "hpid" = NEW.hpid) AS T;

    SELECT tmp."from" INTO NEW."to";

    PERFORM blacklist_control(NEW."from", NEW."to"); -- can't thumb on blacklisted board
    IF tmp."from" <> tmp."to" THEN
        PERFORM blacklist_control(NEW."from", tmp."from"); -- can't thumbs if post was made by blacklisted user
END IF;

IF NEW."vote" = 0 THEN
    DELETE FROM "thumbs" WHERE hpid = NEW.hpid AND "from" = NEW."from";
    RETURN NULL;
END IF;

WITH new_values (hpid, "from", vote) AS (
    VALUES(NEW."hpid", NEW."from", NEW."vote")
),
upsert AS (
    UPDATE "thumbs" AS m
    SET vote = nv.vote
    FROM new_values AS nv
    WHERE m.hpid = nv.hpid AND m."from" = nv."from"
    RETURNING m.*
)

SELECT "vote" INTO NEW."vote"
FROM new_values
WHERE NOT EXISTS (
    SELECT 1
    FROM upsert AS up
    WHERE up.hpid = new_values.hpid AND up."from" = new_values."from"
);

IF NEW."vote" IS NULL THEN -- updated previous vote
    RETURN NULL; --no need to insert new value
END IF;

RETURN NEW;
END $$;


ALTER FUNCTION public.before_insert_thumb() OWNER TO nerdz;

--
-- Name: before_insert_user_post_lurker(); Type: FUNCTION; Schema: public; Owner: nerdz
--

CREATE FUNCTION public.before_insert_user_post_lurker() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE tmp RECORD;
BEGIN
    PERFORM flood_control('"lurkers"', NEW."from");

    SELECT T."to", T."from" INTO tmp FROM (SELECT "to", "from" FROM "posts" WHERE "hpid" = NEW.hpid) AS T;

    SELECT tmp."to" INTO NEW."to";

    PERFORM blacklist_control(NEW."from", NEW."to"); -- can't lurk on blacklisted board
    IF tmp."from" <> tmp."to" THEN
        PERFORM blacklist_control(NEW."from", tmp."from"); -- can't lurk if post was made by blacklisted user
END IF;

IF NEW."from" IN ( SELECT "from" FROM "comments" WHERE hpid = NEW.hpid ) THEN
    RAISE EXCEPTION 'CANT_LURK_IF_POSTED';
END IF;

RETURN NEW;

END $$;


ALTER FUNCTION public.before_insert_user_post_lurker() OWNER TO nerdz;

--
-- Name: blacklist_control(bigint, bigint); Type: FUNCTION; Schema: public; Owner: nerdz
--

CREATE FUNCTION public.blacklist_control(me bigint, other bigint) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- templates and other implementations must handle exceptions with localized functions
    IF me IN (SELECT "from" FROM blacklist WHERE "to" = other) THEN
        RAISE EXCEPTION 'YOU_BLACKLISTED_THIS_USER';
END IF;

IF me IN (SELECT "to" FROM blacklist WHERE "from" = other) THEN
    RAISE EXCEPTION 'YOU_HAVE_BEEN_BLACKLISTED';
END IF;
END $$;


ALTER FUNCTION public.blacklist_control(me bigint, other bigint) OWNER TO nerdz;

--
-- Name: flood_control(regclass, bigint, text); Type: FUNCTION; Schema: public; Owner: nerdz
--

CREATE FUNCTION public.flood_control(tbl regclass, flooder bigint, message text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE now timestamp(0) without time zone;
lastAction timestamp(0) without time zone;
interv interval minute to second;
myLastMessage text;
postId text;
BEGIN
    EXECUTE 'SELECT MAX("time") FROM ' || tbl || ' WHERE "from" = ' || flooder || ';' INTO lastAction;
    now := (now() at time zone 'utc');

    SELECT time FROM flood_limits WHERE table_name = tbl INTO interv;

    IF now - lastAction < interv THEN
        RAISE EXCEPTION 'FLOOD ~%~', interv - (now - lastAction);
END IF;

-- duplicate messagee
IF message IS NOT NULL AND tbl IN ('comments', 'groups_comments', 'posts', 'groups_posts') THEN

    SELECT CASE
        WHEN tbl IN ('comments', 'groups_comments') THEN 'hcid'
        WHEN tbl IN ('posts', 'groups_posts') THEN 'hpid'
        ELSE 'pmid'
END AS columnName INTO postId;

EXECUTE 'SELECT "message" FROM ' || tbl || ' WHERE "from" = ' || flooder || ' AND ' || postId || ' = (
    SELECT MAX(' || postId ||') FROM ' || tbl || ' WHERE "from" = ' || flooder || ')' INTO myLastMessage;

IF myLastMessage = message THEN
    RAISE EXCEPTION 'FLOOD';
END IF;
END IF;
END $$;


ALTER FUNCTION public.flood_control(tbl regclass, flooder bigint, message text) OWNER TO nerdz;

--
-- Name: group_comment(); Type: FUNCTION; Schema: public; Owner: nerdz
--

CREATE FUNCTION public.group_comment() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM hashtag(NEW.message, NEW.hpid, true, NEW.from, NEW.time);
    PERFORM mention(NEW."from", NEW.message, NEW.hpid, true);
    -- edit support
    IF TG_OP = 'UPDATE' THEN
        INSERT INTO groups_comments_revisions(hcid, time, message, rev_no)
        VALUES(OLD.hcid, OLD.time, OLD.message, (
                SELECT COUNT(hcid) + 1 FROM groups_comments_revisions WHERE hcid = OLD.hcid
        ));

    --notify only if it's the last comment in the post
    IF OLD.hcid <> (SELECT MAX(hcid) FROM groups_comments WHERE hpid = NEW.hpid) THEN
        RETURN NULL;
END IF;
END IF;


-- if I commented the post, I stop lurking
DELETE FROM "groups_lurkers" WHERE "hpid" = NEW."hpid" AND "from" = NEW."from";

WITH no_notify("user") AS (
    -- blacklist
    (
        SELECT "from" FROM "blacklist" WHERE "to" = NEW."from"
        UNION
        SELECT "to" FROM "blacklist" WHERE "from" = NEW."from"
    )
    UNION -- users that locked the notifications for all the thread
    SELECT "user" FROM "groups_posts_no_notify" WHERE "hpid" = NEW."hpid"
    UNION -- users that locked notifications from me in this thread
    SELECT "to" FROM "groups_comments_no_notify" WHERE "from" = NEW."from" AND "hpid" = NEW."hpid"
    UNION -- users mentioned in this post (already notified, with the mention)
    SELECT "to" FROM "mentions" WHERE "g_hpid" = NEW.hpid AND to_notify IS TRUE
    UNION
    SELECT NEW."from"
),
to_notify("user") AS (
    SELECT DISTINCT "from" FROM "groups_comments" WHERE "hpid" = NEW."hpid"
    UNION
    SELECT "from" FROM "groups_lurkers" WHERE "hpid" = NEW."hpid"
    UNION
    SELECT "from" FROM "groups_posts" WHERE "hpid" = NEW."hpid"
),
real_notify("user") AS (
    -- avoid to add rows with the same primary key
    SELECT "user" FROM (
        SELECT "user" FROM to_notify
        EXCEPT
        (
            SELECT "user" FROM no_notify
            UNION
            SELECT "to" FROM "groups_comments_notify" WHERE "hpid" = NEW."hpid"
        )
    ) AS T1
)

INSERT INTO "groups_comments_notify"("from","to","hpid","time") (
    SELECT NEW."from", "user", NEW."hpid", NEW."time" FROM real_notify
);

RETURN NULL;
 END $$;


ALTER FUNCTION public.group_comment() OWNER TO nerdz;

--
-- Name: group_comment_edit_control(); Type: FUNCTION; Schema: public; Owner: nerdz
--

CREATE FUNCTION public.group_comment_edit_control() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE postFrom int8;
BEGIN
    IF OLD.editable IS FALSE THEN
        RAISE EXCEPTION 'NOT_EDITABLE';
END IF;

-- update time
SELECT (now() at time zone 'utc') INTO NEW.time;

NEW.message = message_control(NEW.message);
PERFORM flood_control('"groups_comments"', NEW."from", NEW.message);

SELECT T."from" INTO postFrom FROM (SELECT "from" FROM "groups_posts" WHERE hpid = NEW.hpid) AS T;
PERFORM blacklist_control(NEW."from", postFrom); --blacklisted post creator

RETURN NEW;
END $$;


ALTER FUNCTION public.group_comment_edit_control() OWNER TO nerdz;

--
-- Name: group_interactions(bigint, bigint); Type: FUNCTION; Schema: public; Owner: nerdz
--

CREATE FUNCTION public.group_interactions(me bigint, grp bigint) RETURNS SETOF record
    LANGUAGE plpgsql
    AS $$
DECLARE tbl text;
ret record;
query text;
BEGIN
    FOR tbl IN (SELECT unnest(array['groups_members', 'groups_followers', 'groups_comments', 'groups_comment_thumbs', 'groups_lurkers', 'groups_owners', 'groups_thumbs', 'groups_posts'])) LOOP
        query := interactions_query_builder(tbl, me, grp, true);
        FOR ret IN EXECUTE query LOOP
            RETURN NEXT ret;
END LOOP;
END LOOP;
RETURN;
END $$;


ALTER FUNCTION public.group_interactions(me bigint, grp bigint) OWNER TO nerdz;

--
-- Name: group_post_control(); Type: FUNCTION; Schema: public; Owner: nerdz
--

CREATE FUNCTION public.group_post_control() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE group_owner int8;
open_group boolean;
members int8[];
BEGIN
    NEW.message = message_control(NEW.message);

    IF TG_OP = 'INSERT' THEN -- no flood control on update
        PERFORM flood_control('"groups_posts"', NEW."from", NEW.message);
END IF;

SELECT "from" INTO group_owner FROM "groups_owners" WHERE "to" = NEW."to";
SELECT "open" INTO open_group FROM groups WHERE "counter" = NEW."to";

IF group_owner <> NEW."from" AND
    (
        open_group IS FALSE AND NEW."from" NOT IN (
            SELECT "from" FROM "groups_members" WHERE "to" = NEW."to" )
    )
    THEN
    RAISE EXCEPTION 'CLOSED_PROJECT';
END IF;

IF open_group IS FALSE THEN -- if the group is closed, blacklist works
    PERFORM blacklist_control(NEW."from", group_owner);
END IF;

IF TG_OP = 'UPDATE' THEN
    SELECT (now() at time zone 'utc') INTO NEW.time;
ELSE
    SELECT "pid" INTO NEW.pid FROM (
        SELECT COALESCE( (SELECT "pid" + 1 as "pid" FROM "groups_posts"
                WHERE "to" = NEW."to"
                ORDER BY "hpid" DESC
                FETCH FIRST ROW ONLY), 1) AS "pid"
    ) AS T1;
END IF;

IF NEW."from" <> group_owner AND NEW."from" NOT IN (
    SELECT "from" FROM "groups_members" WHERE "to" = NEW."to"
    ) THEN
    SELECT false INTO NEW.news; -- Only owner and members can send news
END IF;

-- if to = GLOBAL_NEWS set the news filed to true
IF NEW."to" = (SELECT counter FROM special_groups where "role" = 'GLOBAL_NEWS') THEN
    SELECT true INTO NEW.news;
END IF;

RETURN NEW;
END $$;


ALTER FUNCTION public.group_post_control() OWNER TO nerdz;

--
-- Name: groups_post_update(); Type: FUNCTION; Schema: public; Owner: nerdz
--

CREATE FUNCTION public.groups_post_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO groups_posts_revisions(hpid, time, message, rev_no) VALUES(OLD.hpid, OLD.time, OLD.message,
        (SELECT COUNT(hpid) +1 FROM groups_posts_revisions WHERE hpid = OLD.hpid));

    PERFORM hashtag(NEW.message, NEW.hpid, true, NEW.from, NEW.time);
    PERFORM mention(NEW."from", NEW.message, NEW.hpid, true);
    RETURN NULL;
 END $$;


ALTER FUNCTION public.groups_post_update() OWNER TO nerdz;

--
-- Name: handle_groups_on_user_delete(bigint); Type: FUNCTION; Schema: public; Owner: nerdz
--

CREATE FUNCTION public.handle_groups_on_user_delete(usercounter bigint) RETURNS void
    LANGUAGE plpgsql
    AS $$
declare r RECORD;
newOwner int8;
begin
    FOR r IN SELECT "to" FROM "groups_owners" WHERE "from" = userCounter LOOP
        IF EXISTS (select "from" FROM groups_members where "to" = r."to") THEN
            SELECT gm."from" INTO newowner FROM groups_members gm
            WHERE "to" = r."to" AND "time" = (
                SELECT min(time) FROM groups_members WHERE "to" = r."to"
            );

            UPDATE "groups_owners" SET "from" = newOwner, to_notify = TRUE WHERE "to" = r."to";
            DELETE FROM groups_members WHERE "from" = newOwner;
END IF;
-- else, the foreing key remains and the group will be dropped
END LOOP;
END $$;


ALTER FUNCTION public.handle_groups_on_user_delete(usercounter bigint) OWNER TO nerdz;

--
-- Name: hashtag(text, bigint, boolean, bigint, timestamp without time zone); Type: FUNCTION; Schema: public; Owner: nerdz
--

CREATE FUNCTION public.hashtag(message text, hpid bigint, grp boolean, from_u bigint, m_time timestamp without time zone) RETURNS void
    LANGUAGE plpgsql
    AS $$
declare field text;
regex text;
BEGIN
    IF grp THEN
        field := 'g_hpid';
    ELSE
        field := 'u_hpid';
END IF;

regex = '((?![\d]+[[^\w]+|])[\w]{1,44})';

message = quote_literal(message);

EXECUTE '
insert into posts_classification(' || field || ' , "from", time, tag)
select distinct ' || hpid ||', ' || from_u || ', ''' || m_time || '''::timestamp, tmp.matchedTag[1] from (
    -- 1: existing hashtags
    select concat(''{#'', a.matchedTag[1], ''}'')::text[] as matchedTag from (
        select regexp_matches(' || strip_tags(message) || ', ''(?:\s|^|\W)#' || regex || ''', ''gi'')
        as matchedTag
    ) as a
    union distinct -- 2: spoiler
    select concat(''{#'', b.matchedTag[1], ''}'')::text[] from (
        select regexp_matches(' || message || ', ''\[spoiler=' || regex || '\]'', ''gi'')
        as matchedTag
    ) as b
    union distinct -- 3: languages
    select concat(''{#'', c.matchedTag[1], ''}'')::text[] from (
        select regexp_matches(' || message || ', ''\[code=' || regex || '\]'', ''gi'')
        as matchedTag
    ) as c
    union distinct -- 4: languages, short tag
    select concat(''{#'', d.matchedTag[1], ''}'')::text[] from (
        select regexp_matches(' || message || ', ''\[c=' || regex || '\]'', ''gi'')
        as matchedTag
    ) as d
) tmp
where not exists (
    select 1
    from posts_classification p
    where ' || field ||'  = ' || hpid || ' and
    p.tag = tmp.matchedTag[1] and
    p.from = ' || from_u || ' -- store user association with tag even if tag already exists
)';
END $$;


ALTER FUNCTION public.hashtag(message text, hpid bigint, grp boolean, from_u bigint, m_time timestamp without time zone) OWNER TO nerdz;

--
-- Name: interactions_query_builder(text, bigint, bigint, boolean); Type: FUNCTION; Schema: public; Owner: nerdz
--

CREATE FUNCTION public.interactions_query_builder(tbl text, me bigint, other bigint, grp boolean) RETURNS text
    LANGUAGE plpgsql
    AS $$
declare ret text;
begin
    ret := 'SELECT ''' || tbl || '''::text';
    IF NOT grp THEN
        ret = ret || ' ,t."from", t."to"';
END IF;
ret = ret || ', t."time" ';
--joins
IF tbl ILIKE '%comments' OR tbl = 'thumbs' OR tbl = 'groups_thumbs' OR tbl ILIKE '%lurkers'
    THEN

    ret = ret || ' , p."pid", p."to" FROM "' || tbl || '" t INNER JOIN "';
    IF grp THEN
        ret = ret || 'groups_';
END IF;
ret = ret || 'posts" p ON p.hpid = t.hpid';

        ELSIF tbl ILIKE '%posts' THEN

            ret = ret || ', "pid", "to" FROM "' || tbl || '" t';

        ELSIF tbl ILIKE '%comment_thumbs' THEN

            ret = ret || ', p."pid", p."to" FROM "';

            IF grp THEN
                ret = ret || 'groups_';
END IF;

ret = ret || 'comments" c INNER JOIN "' || tbl || '" t
ON t.hcid = c.hcid
INNER JOIN "';

IF grp THEN
    ret = ret || 'groups_';
END IF;

ret = ret || 'posts" p ON p.hpid = c.hpid';

        ELSE
            ret = ret || ', null::int8, null::int8  FROM ' || tbl || ' t ';

END IF;
--conditions
ret = ret || ' WHERE (t."from" = '|| me ||' AND t."to" = '|| other ||')';

IF NOT grp THEN
    ret = ret || ' OR (t."from" = '|| other ||' AND t."to" = '|| me ||')';
END IF;

RETURN ret;
end $$;


ALTER FUNCTION public.interactions_query_builder(tbl text, me bigint, other bigint, grp boolean) OWNER TO nerdz;

--
-- Name: login(text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.login(_username text, _pass text, OUT ret boolean) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
begin
	-- begin legacy migration
	if (select length(password) = 40
			from users
			where lower(username) = lower(_username) and password = encode(digest(_pass, 'SHA1'), 'HEX')
	) then
		update users set password = crypt(_pass, gen_salt('bf', 7)) where lower(username) = lower(_username);
	end if;
	-- end legacy migration
	select password = crypt(_pass, users.password) into ret
	from users
	where lower(username) = lower(_username);
end $$;


ALTER FUNCTION public.login(_username text, _pass text, OUT ret boolean) OWNER TO postgres;

--
-- Name: mention(bigint, text, bigint, boolean); Type: FUNCTION; Schema: public; Owner: nerdz
--

CREATE FUNCTION public.mention(me bigint, message text, hpid bigint, grp boolean) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE field text;
posts_notify_tbl text;
comments_notify_tbl text;
posts_no_notify_tbl text;
comments_no_notify_tbl text;
project record;
owner int8;
other int8;
matches text[];
username text;
found boolean;
BEGIN
    -- prepare tables
    IF grp THEN
        EXECUTE 'SELECT closed FROM groups_posts WHERE hpid = ' || hpid INTO found;
        IF found THEN
            RETURN;
END IF;
posts_notify_tbl = 'groups_notify';
posts_no_notify_tbl = 'groups_posts_no_notify';

comments_notify_tbl = 'groups_comments_notify';
comments_no_notify_tbl = 'groups_comments_no_notify';
    ELSE
        EXECUTE 'SELECT closed FROM posts WHERE hpid = ' || hpid INTO found;
        IF found THEN
            RETURN;
END IF;
posts_notify_tbl = 'posts_notify';
posts_no_notify_tbl = 'posts_no_notify';

comments_notify_tbl = 'comments_notify';
comments_no_notify_tbl = 'comments_no_notify';
END IF;

-- extract [user]username[/user]
message = quote_literal(message);
FOR matches IN
    EXECUTE 'select regexp_matches(' || message || ',
        ''(?!\[(?:url|code|video|yt|youtube|music|img|twitter)[^\]]*\])\[user\](.+?)\[/user\](?![^\[]*\[\/(?:url|code|video|yt|youtube|music|img|twitter)\])'', ''gi''
    )' LOOP

    username = matches[1];
    -- if username exists
    EXECUTE 'SELECT counter FROM users WHERE LOWER(username) = LOWER(' || quote_literal(username) || ');' INTO other;
    IF other IS NULL OR other = me THEN
        CONTINUE;
END IF;

-- check if 'other' is in notfy list.
-- if it is, continue, since he will receive notification about this post anyway
EXECUTE 'SELECT ' || other || ' IN (
    (SELECT "to" FROM "' || posts_notify_tbl || '" WHERE hpid = ' || hpid || ')
    UNION
    (SELECT "to" FROM "' || comments_notify_tbl || '" WHERE hpid = ' || hpid || ')
)' INTO found;

IF found THEN
    CONTINUE;
END IF;

-- check if 'ohter' disabled notification from post hpid, if yes -> skip
EXECUTE 'SELECT ' || other || ' IN (SELECT "user" FROM "' || posts_no_notify_tbl || '" WHERE hpid = ' || hpid || ')' INTO found;
IF found THEN
    CONTINUE;
END IF;

--check if 'other' disabled notification from 'me' in post hpid, if yes -> skip
EXECUTE 'SELECT ' || other || ' IN (SELECT "to" FROM "' || comments_no_notify_tbl || '" WHERE hpid = ' || hpid || ' AND "from" = ' || me || ')' INTO found;

IF found THEN
    CONTINUE;
END IF;

-- blacklist control
BEGIN
    PERFORM blacklist_control(me, other);

    IF grp THEN
        EXECUTE 'SELECT counter, visible
        FROM groups WHERE "counter" = (
            SELECT "to" FROM groups_posts p WHERE p.hpid = ' || hpid || ');'
        INTO project;

        select "from" INTO owner FROM groups_owners WHERE "to" = project.counter;
        -- other can't access groups if the owner blacklisted him
        PERFORM blacklist_control(owner, other);

        -- if the project is NOT visible and other is not the owner or a member
        IF project.visible IS FALSE AND other NOT IN (
            SELECT "from" FROM groups_members WHERE "to" = project.counter
            UNION
            SELECT owner
            ) THEN
            RETURN;
END IF;
END IF;

EXCEPTION
            WHEN OTHERS THEN
                CONTINUE;
END;

IF grp THEN
    field := 'g_hpid';
ELSE
    field := 'u_hpid';
END IF;

-- if here and mentions does not exists, insert
EXECUTE 'INSERT INTO mentions(' || field || ' , "from", "to")
SELECT ' || hpid || ', ' || me || ', '|| other ||'
WHERE NOT EXISTS (
    SELECT 1 FROM mentions
    WHERE "' || field || '" = ' || hpid || ' AND "to" = ' || other || '
)';

END LOOP;

END $$;


ALTER FUNCTION public.mention(me bigint, message text, hpid bigint, grp boolean) OWNER TO nerdz;

--
-- Name: message_control(text); Type: FUNCTION; Schema: public; Owner: nerdz
--

CREATE FUNCTION public.message_control(message text) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE ret text;
BEGIN
    SELECT trim(message) INTO ret;
    IF char_length(ret) = 0 THEN
        RAISE EXCEPTION 'NO_EMPTY_MESSAGE';
END IF;
RETURN ret;
END $$;


ALTER FUNCTION public.message_control(message text) OWNER TO nerdz;

--
-- Name: post_control(); Type: FUNCTION; Schema: public; Owner: nerdz
--

CREATE FUNCTION public.post_control() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.message = message_control(NEW.message);

    IF TG_OP = 'INSERT' THEN -- no flood control on update
        PERFORM flood_control('"posts"', NEW."from", NEW.message);
END IF;

PERFORM blacklist_control(NEW."from", NEW."to");

IF( NEW."to" <> NEW."from" AND
    (SELECT "closed" FROM "profiles" WHERE "counter" = NEW."to") IS TRUE AND 
    NEW."from" NOT IN (SELECT "to" FROM whitelist WHERE "from" = NEW."to")
    )
    THEN
    RAISE EXCEPTION 'CLOSED_PROFILE';
END IF;


IF TG_OP = 'UPDATE' THEN -- no pid increment
    SELECT (now() at time zone 'utc') INTO NEW.time;
ELSE
    SELECT "pid" INTO NEW.pid FROM (
        SELECT COALESCE( (SELECT "pid" + 1 as "pid" FROM "posts"
                WHERE "to" = NEW."to"
                ORDER BY "hpid" DESC
                FETCH FIRST ROW ONLY), 1 ) AS "pid"
    ) AS T1;
END IF;

IF NEW."to" <> NEW."from" THEN -- can't write news to others board
    SELECT false INTO NEW.news;
END IF;

-- if to = GLOBAL_NEWS set the news filed to true
IF NEW."to" = (SELECT counter FROM special_users where "role" = 'GLOBAL_NEWS') THEN
    SELECT true INTO NEW.news;
END IF;

RETURN NEW;
END $$;


ALTER FUNCTION public.post_control() OWNER TO nerdz;

--
-- Name: post_update(); Type: FUNCTION; Schema: public; Owner: nerdz
--

CREATE FUNCTION public.post_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO posts_revisions(hpid, time, message, rev_no) VALUES(OLD.hpid, OLD.time, OLD.message,
        (SELECT COUNT(hpid) +1 FROM posts_revisions WHERE hpid = OLD.hpid));

    PERFORM hashtag(NEW.message, NEW.hpid, false, NEW.from, NEW.time);
    PERFORM mention(NEW."from", NEW.message, NEW.hpid, false);
    RETURN NULL;
END $$;


ALTER FUNCTION public.post_update() OWNER TO nerdz;

--
-- Name: strip_tags(text); Type: FUNCTION; Schema: public; Owner: nerdz
--

CREATE FUNCTION public.strip_tags(message text) RETURNS text
    LANGUAGE plpgsql
    AS $$
begin
    return regexp_replace(regexp_replace(
            regexp_replace(regexp_replace(
                    regexp_replace(regexp_replace(
                            regexp_replace(regexp_replace(
                                    regexp_replace(message,
                                        '\[url[^\]]*?\](.*)\[/url\]',' ','gi'),
                                    '\[code=[^\]]+\].+?\[/code\]',' ','gi'),
                                '\[c=[^\]]+\].+?\[/c\]',' ','gi'),
                            '\[video\].+?\[/video\]',' ','gi'),
                        '\[yt\].+?\[/yt\]',' ','gi'),
                    '\[youtube\].+?\[/youtube\]',' ','gi'),
                '\[music\].+?\[/music\]',' ','gi'),
            '\[img\].+?\[/img\]',' ','gi'),
        '\[twitter\].+?\[/twitter\]',' ','gi');
end $$;


ALTER FUNCTION public.strip_tags(message text) OWNER TO nerdz;

--
-- Name: trigger_json_notification(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.trigger_json_notification() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
keys text[];
vals text[];
other_info record;
what text;
tmp text;
BEGIN
    what = TG_ARGV[0];

    keys[0] := 'type';
    vals[0] := what;

    IF what <> 'project_post' THEN
        keys[1] := 'username';
        keys[2] := 'name';
        keys[3] := 'surname';
        keys[4] := 'timestamp';
        SELECT username,name,surname from users where counter = NEW."from" INTO other_info;

        vals[1] := other_info.username;
        vals[2] := other_info.name;
        vals[3] := other_info.surname;
        vals[4] := EXTRACT(EPOCH FROM NEW.time);
END IF;

IF what = 'pm' THEN
    keys[5] := 'message';
    vals[5] := NEW.message;
ELSIF what = 'user_comment' THEN
    keys[5] := 'message';
    SELECT message INTO tmp FROM comments
    WHERE hpid = NEW.hpid AND "from" = NEW."from"
    ORDER BY hcid DESC LIMIT 1;
    vals[5] := tmp;

    keys[6] := 'profile';
    keys[7] := 'pid';

    SELECT u.username INTO tmp FROM users u WHERE u.counter = (
        SELECT "to" FROM posts WHERE hpid = NEW.hpid);
    vals[6] := tmp;

    SELECT pid INTO tmp FROM posts WHERE hpid = NEW.hpid;
    vals[7] := tmp;
ELSIF what = 'user_post' THEN
    keys[5] := 'profile';
    keys[6] := 'pid';
    SELECT username INTO tmp FROM users WHERE counter = NEW."to";
    vals[5] := tmp;

    SELECT pid INTO tmp FROM posts WHERE hpid = NEW.hpid;
    vals[6] := tmp;
ELSIF what = 'project_comment' THEN
    keys[5] := 'message';
    SELECT message INTO tmp FROM groups_comments
    WHERE hpid = NEW.hpid AND "from" = NEW."from"
    ORDER BY hcid DESC LIMIT 1;
    vals[5] := tmp;

    keys[6] := 'project';
    keys[7] := 'pid';

    SELECT g.name INTO tmp FROM groups g WHERE g.counter = (
        SELECT "to" FROM groups_posts WHERE hpid = NEW.hpid);
    vals[6] := tmp;

    SELECT pid INTO tmp FROM groups_posts WHERE hpid = NEW.hpid;
    vals[7] := tmp;
ELSIF what = 'project_post' THEN
    keys[1] := 'project';
    SELECT name INTO tmp FROM groups WHERE counter = NEW."from";
    vals[1] := tmp;

    keys[2] := 'pid';
    SELECT pid INTO tmp FROM groups_posts WHERE hpid = NEW.hpid;
    vals[2] := tmp;
ELSIF what = 'follower' THEN
    -- nothing to do, keys[0...4] are enough
    NULL;
ELSIF what IN ('project_follower', 'project_member', 'project_owner') THEN
    keys[5] := 'project';
    SELECT name INTO tmp FROM groups WHERE counter = NEW."to";
    vals[5] := tmp;
ELSIF what = 'user_mention' THEN
    keys[5] := 'profile';
    keys[6] := 'pid';
    SELECT username INTO tmp FROM users WHERE counter = (
        SELECT "to" FROM posts WHERE hpid = NEW.u_hpid);
    vals[5] := tmp;

    SELECT pid INTO tmp FROM posts WHERE hpid = NEW.u_hpid;
    vals[6] := tmp;
ELSIF what = 'project_mention' THEN
    keys[5] := 'project';
    keys[6] := 'pid';
    SELECT name INTO tmp FROM groups WHERE counter = (
        SELECT "to" FROM groups_posts WHERE hpid = NEW.g_hpid);
    vals[5] := tmp;

    SELECT pid INTO tmp FROM groups_posts WHERE hpid = NEW.g_hpid;
    vals[6] := tmp;
ELSE
    RETURN NULL;
END IF;

PERFORM pg_notify('u' || NEW."to", '{"data": ' || jsonb_object(keys, vals)::text || '}');
RETURN NULL;
END $$;


ALTER FUNCTION public.trigger_json_notification() OWNER TO postgres;

--
-- Name: user_comment(); Type: FUNCTION; Schema: public; Owner: nerdz
--

CREATE FUNCTION public.user_comment() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM hashtag(NEW.message, NEW.hpid, false, NEW.from, NEW.time);
    PERFORM mention(NEW."from", NEW.message, NEW.hpid, false);
    -- edit support
    IF TG_OP = 'UPDATE' THEN
        INSERT INTO comments_revisions(hcid, time, message, rev_no)
        VALUES(OLD.hcid, OLD.time, OLD.message, (
                SELECT COUNT(hcid) + 1 FROM comments_revisions WHERE hcid = OLD.hcid
        ));

    --notify only if it's the last comment in the post
    IF OLD.hcid <> (SELECT MAX(hcid) FROM comments WHERE hpid = NEW.hpid) THEN
        RETURN NULL;
END IF;
END IF;

-- if I commented the post, I stop lurking
DELETE FROM "lurkers" WHERE "hpid" = NEW."hpid" AND "from" = NEW."from";

WITH no_notify("user") AS (
    -- blacklist
    (
        SELECT "from" FROM "blacklist" WHERE "to" = NEW."from"
        UNION
        SELECT "to" FROM "blacklist" WHERE "from" = NEW."from"
    )
    UNION -- users that locked the notifications for all the thread
    SELECT "user" FROM "posts_no_notify" WHERE "hpid" = NEW."hpid"
    UNION -- users that locked notifications from me in this thread
    SELECT "to" FROM "comments_no_notify" WHERE "from" = NEW."from" AND "hpid" = NEW."hpid"
    UNION -- users mentioned in this post (already notified, with the mention)
    SELECT "to" FROM "mentions" WHERE "u_hpid" = NEW.hpid AND to_notify IS TRUE
    UNION
    SELECT NEW."from"
),
to_notify("user") AS (
    SELECT DISTINCT "from" FROM "comments" WHERE "hpid" = NEW."hpid"
    UNION
    SELECT "from" FROM "lurkers" WHERE "hpid" = NEW."hpid"
    UNION
    SELECT "from" FROM "posts" WHERE "hpid" = NEW."hpid"
    UNION
    SELECT "to" FROM "posts" WHERE "hpid" = NEW."hpid"
),
real_notify("user") AS (
    -- avoid to add rows with the same primary key
    SELECT "user" FROM (
        SELECT "user" FROM to_notify
        EXCEPT
        (
            SELECT "user" FROM no_notify
            UNION
            SELECT "to" AS "user" FROM "comments_notify" WHERE "hpid" = NEW."hpid"
        )
    ) AS T1
)

INSERT INTO "comments_notify"("from","to","hpid","time") (
    SELECT NEW."from", "user", NEW."hpid", NEW."time" FROM real_notify
);

RETURN NULL;
END $$;


ALTER FUNCTION public.user_comment() OWNER TO nerdz;

--
-- Name: user_comment_edit_control(); Type: FUNCTION; Schema: public; Owner: nerdz
--

CREATE FUNCTION public.user_comment_edit_control() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF OLD.editable IS FALSE THEN
        RAISE EXCEPTION 'NOT_EDITABLE';
END IF;

-- update time
SELECT (now() at time zone 'utc') INTO NEW.time;

NEW.message = message_control(NEW.message);
PERFORM flood_control('"comments"', NEW."from", NEW.message);
PERFORM blacklist_control(NEW."from", NEW."to");

RETURN NEW;
END $$;


ALTER FUNCTION public.user_comment_edit_control() OWNER TO nerdz;

--
-- Name: user_interactions(bigint, bigint); Type: FUNCTION; Schema: public; Owner: nerdz
--

CREATE FUNCTION public.user_interactions(me bigint, other bigint) RETURNS SETOF record
    LANGUAGE plpgsql
    AS $$
DECLARE tbl text;
ret record;
query text;
begin
    FOR tbl IN (SELECT unnest(array['blacklist', 'comment_thumbs', 'comments', 'followers', 'lurkers', 'mentions', 'pms', 'posts', 'whitelist'])) LOOP
        query := interactions_query_builder(tbl, me, other, false);
        FOR ret IN EXECUTE query LOOP
            RETURN NEXT ret;
END LOOP;
END LOOP;
RETURN;
END $$;


ALTER FUNCTION public.user_interactions(me bigint, other bigint) OWNER TO nerdz;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: ban; Type: TABLE; Schema: public; Owner: nerdz
--

CREATE TABLE public.ban (
    "user" bigint NOT NULL,
    motivation text DEFAULT 'No reason given'::text NOT NULL,
    "time" timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);


ALTER TABLE public.ban OWNER TO nerdz;

--
-- Name: blacklist; Type: TABLE; Schema: public; Owner: nerdz
--

CREATE TABLE public.blacklist (
    "from" bigint NOT NULL,
    "to" bigint NOT NULL,
    motivation text DEFAULT 'No reason given'::text,
    "time" timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    counter bigint NOT NULL
);


ALTER TABLE public.blacklist OWNER TO nerdz;

--
-- Name: blacklist_id_seq; Type: SEQUENCE; Schema: public; Owner: nerdz
--

CREATE SEQUENCE public.blacklist_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.blacklist_id_seq OWNER TO nerdz;

--
-- Name: blacklist_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nerdz
--

ALTER SEQUENCE public.blacklist_id_seq OWNED BY public.blacklist.counter;


--
-- Name: bookmarks; Type: TABLE; Schema: public; Owner: nerdz
--

CREATE TABLE public.bookmarks (
    "from" bigint NOT NULL,
    hpid bigint NOT NULL,
    "time" timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    counter bigint NOT NULL
);


ALTER TABLE public.bookmarks OWNER TO nerdz;

--
-- Name: bookmarks_id_seq; Type: SEQUENCE; Schema: public; Owner: nerdz
--

CREATE SEQUENCE public.bookmarks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.bookmarks_id_seq OWNER TO nerdz;

--
-- Name: bookmarks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nerdz
--

ALTER SEQUENCE public.bookmarks_id_seq OWNED BY public.bookmarks.counter;


--
-- Name: comment_thumbs; Type: TABLE; Schema: public; Owner: nerdz
--

CREATE TABLE public.comment_thumbs (
    hcid bigint NOT NULL,
    "from" bigint NOT NULL,
    vote smallint NOT NULL,
    "time" timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    "to" bigint NOT NULL,
    counter bigint NOT NULL,
    CONSTRAINT chkvote CHECK ((vote = ANY (ARRAY['-1'::integer, 0, 1])))
);


ALTER TABLE public.comment_thumbs OWNER TO nerdz;

--
-- Name: comment_thumbs_id_seq; Type: SEQUENCE; Schema: public; Owner: nerdz
--

CREATE SEQUENCE public.comment_thumbs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.comment_thumbs_id_seq OWNER TO nerdz;

--
-- Name: comment_thumbs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nerdz
--

ALTER SEQUENCE public.comment_thumbs_id_seq OWNED BY public.comment_thumbs.counter;


--
-- Name: comments; Type: TABLE; Schema: public; Owner: nerdz
--

CREATE TABLE public.comments (
    "from" bigint NOT NULL,
    "to" bigint NOT NULL,
    hpid bigint NOT NULL,
    message text NOT NULL,
    "time" timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    hcid bigint NOT NULL,
    editable boolean DEFAULT true NOT NULL,
    lang character varying(2) DEFAULT 'en'::character varying NOT NULL
);


ALTER TABLE public.comments OWNER TO nerdz;

--
-- Name: comments_hcid_seq; Type: SEQUENCE; Schema: public; Owner: nerdz
--

CREATE SEQUENCE public.comments_hcid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.comments_hcid_seq OWNER TO nerdz;

--
-- Name: comments_hcid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nerdz
--

ALTER SEQUENCE public.comments_hcid_seq OWNED BY public.comments.hcid;


--
-- Name: comments_no_notify; Type: TABLE; Schema: public; Owner: nerdz
--

CREATE TABLE public.comments_no_notify (
    "from" bigint NOT NULL,
    "to" bigint NOT NULL,
    hpid bigint NOT NULL,
    "time" timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    counter bigint NOT NULL
);


ALTER TABLE public.comments_no_notify OWNER TO nerdz;

--
-- Name: comments_no_notify_id_seq; Type: SEQUENCE; Schema: public; Owner: nerdz
--

CREATE SEQUENCE public.comments_no_notify_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.comments_no_notify_id_seq OWNER TO nerdz;

--
-- Name: comments_no_notify_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nerdz
--

ALTER SEQUENCE public.comments_no_notify_id_seq OWNED BY public.comments_no_notify.counter;


--
-- Name: comments_notify; Type: TABLE; Schema: public; Owner: nerdz
--

CREATE TABLE public.comments_notify (
    "from" bigint NOT NULL,
    "to" bigint NOT NULL,
    hpid bigint NOT NULL,
    "time" timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    counter bigint NOT NULL,
    to_notify boolean DEFAULT true NOT NULL
);


ALTER TABLE public.comments_notify OWNER TO nerdz;

--
-- Name: comments_notify_id_seq; Type: SEQUENCE; Schema: public; Owner: nerdz
--

CREATE SEQUENCE public.comments_notify_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.comments_notify_id_seq OWNER TO nerdz;

--
-- Name: comments_notify_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nerdz
--

ALTER SEQUENCE public.comments_notify_id_seq OWNED BY public.comments_notify.counter;


--
-- Name: comments_revisions; Type: TABLE; Schema: public; Owner: nerdz
--

CREATE TABLE public.comments_revisions (
    hcid bigint NOT NULL,
    message text NOT NULL,
    "time" timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    rev_no integer DEFAULT 0 NOT NULL,
    counter bigint NOT NULL
);


ALTER TABLE public.comments_revisions OWNER TO nerdz;

--
-- Name: comments_revisions_id_seq; Type: SEQUENCE; Schema: public; Owner: nerdz
--

CREATE SEQUENCE public.comments_revisions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.comments_revisions_id_seq OWNER TO nerdz;

--
-- Name: comments_revisions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nerdz
--

ALTER SEQUENCE public.comments_revisions_id_seq OWNED BY public.comments_revisions.counter;


--
-- Name: deleted_users; Type: TABLE; Schema: public; Owner: nerdz
--

CREATE TABLE public.deleted_users (
    counter bigint NOT NULL,
    username character varying(90) NOT NULL,
    "time" timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    motivation text
);


ALTER TABLE public.deleted_users OWNER TO nerdz;

--
-- Name: flood_limits; Type: TABLE; Schema: public; Owner: nerdz
--

CREATE TABLE public.flood_limits (
    table_name regclass NOT NULL,
    "time" interval minute to second NOT NULL
);


ALTER TABLE public.flood_limits OWNER TO nerdz;

--
-- Name: followers; Type: TABLE; Schema: public; Owner: nerdz
--

CREATE TABLE public.followers (
    "from" bigint NOT NULL,
    "to" bigint NOT NULL,
    to_notify boolean DEFAULT true NOT NULL,
    "time" timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    counter bigint NOT NULL
);


ALTER TABLE public.followers OWNER TO nerdz;

--
-- Name: followers_id_seq; Type: SEQUENCE; Schema: public; Owner: nerdz
--

CREATE SEQUENCE public.followers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.followers_id_seq OWNER TO nerdz;

--
-- Name: followers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nerdz
--

ALTER SEQUENCE public.followers_id_seq OWNED BY public.followers.counter;


--
-- Name: groups; Type: TABLE; Schema: public; Owner: nerdz
--

CREATE TABLE public.groups (
    counter bigint NOT NULL,
    description text DEFAULT ''::text NOT NULL,
    name character varying(30) NOT NULL,
    private boolean DEFAULT false NOT NULL,
    photo character varying(350) DEFAULT NULL::character varying,
    website character varying(350) DEFAULT NULL::character varying,
    goal text DEFAULT ''::text NOT NULL,
    visible boolean DEFAULT true NOT NULL,
    open boolean DEFAULT false NOT NULL,
    creation_time timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);


ALTER TABLE public.groups OWNER TO nerdz;

--
-- Name: groups_bookmarks; Type: TABLE; Schema: public; Owner: nerdz
--

CREATE TABLE public.groups_bookmarks (
    "from" bigint NOT NULL,
    hpid bigint NOT NULL,
    "time" timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    counter bigint NOT NULL
);


ALTER TABLE public.groups_bookmarks OWNER TO nerdz;

--
-- Name: groups_bookmarks_id_seq; Type: SEQUENCE; Schema: public; Owner: nerdz
--

CREATE SEQUENCE public.groups_bookmarks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.groups_bookmarks_id_seq OWNER TO nerdz;

--
-- Name: groups_bookmarks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nerdz
--

ALTER SEQUENCE public.groups_bookmarks_id_seq OWNED BY public.groups_bookmarks.counter;


--
-- Name: groups_comment_thumbs; Type: TABLE; Schema: public; Owner: nerdz
--

CREATE TABLE public.groups_comment_thumbs (
    hcid bigint NOT NULL,
    "from" bigint NOT NULL,
    vote smallint NOT NULL,
    "time" timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    "to" bigint NOT NULL,
    counter bigint NOT NULL,
    CONSTRAINT chkgvote CHECK ((vote = ANY (ARRAY['-1'::integer, 0, 1])))
);


ALTER TABLE public.groups_comment_thumbs OWNER TO nerdz;

--
-- Name: groups_comment_thumbs_id_seq; Type: SEQUENCE; Schema: public; Owner: nerdz
--

CREATE SEQUENCE public.groups_comment_thumbs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.groups_comment_thumbs_id_seq OWNER TO nerdz;

--
-- Name: groups_comment_thumbs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nerdz
--

ALTER SEQUENCE public.groups_comment_thumbs_id_seq OWNED BY public.groups_comment_thumbs.counter;


--
-- Name: groups_comments; Type: TABLE; Schema: public; Owner: nerdz
--

CREATE TABLE public.groups_comments (
    "from" bigint NOT NULL,
    "to" bigint NOT NULL,
    hpid bigint NOT NULL,
    message text NOT NULL,
    "time" timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    hcid bigint NOT NULL,
    editable boolean DEFAULT true NOT NULL,
    lang character varying(2) DEFAULT 'en'::character varying NOT NULL
);


ALTER TABLE public.groups_comments OWNER TO nerdz;

--
-- Name: groups_comments_hcid_seq; Type: SEQUENCE; Schema: public; Owner: nerdz
--

CREATE SEQUENCE public.groups_comments_hcid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.groups_comments_hcid_seq OWNER TO nerdz;

--
-- Name: groups_comments_hcid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nerdz
--

ALTER SEQUENCE public.groups_comments_hcid_seq OWNED BY public.groups_comments.hcid;


--
-- Name: groups_comments_no_notify; Type: TABLE; Schema: public; Owner: nerdz
--

CREATE TABLE public.groups_comments_no_notify (
    "from" bigint NOT NULL,
    "to" bigint NOT NULL,
    hpid bigint NOT NULL,
    "time" timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    counter bigint NOT NULL
);


ALTER TABLE public.groups_comments_no_notify OWNER TO nerdz;

--
-- Name: groups_comments_no_notify_id_seq; Type: SEQUENCE; Schema: public; Owner: nerdz
--

CREATE SEQUENCE public.groups_comments_no_notify_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.groups_comments_no_notify_id_seq OWNER TO nerdz;

--
-- Name: groups_comments_no_notify_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nerdz
--

ALTER SEQUENCE public.groups_comments_no_notify_id_seq OWNED BY public.groups_comments_no_notify.counter;


--
-- Name: groups_comments_notify; Type: TABLE; Schema: public; Owner: nerdz
--

CREATE TABLE public.groups_comments_notify (
    "from" bigint NOT NULL,
    "to" bigint NOT NULL,
    hpid bigint NOT NULL,
    "time" timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    counter bigint NOT NULL,
    to_notify boolean DEFAULT true NOT NULL
);


ALTER TABLE public.groups_comments_notify OWNER TO nerdz;

--
-- Name: groups_comments_notify_id_seq; Type: SEQUENCE; Schema: public; Owner: nerdz
--

CREATE SEQUENCE public.groups_comments_notify_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.groups_comments_notify_id_seq OWNER TO nerdz;

--
-- Name: groups_comments_notify_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nerdz
--

ALTER SEQUENCE public.groups_comments_notify_id_seq OWNED BY public.groups_comments_notify.counter;


--
-- Name: groups_comments_revisions; Type: TABLE; Schema: public; Owner: nerdz
--

CREATE TABLE public.groups_comments_revisions (
    hcid bigint NOT NULL,
    message text NOT NULL,
    "time" timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    rev_no integer DEFAULT 0 NOT NULL,
    counter bigint NOT NULL
);


ALTER TABLE public.groups_comments_revisions OWNER TO nerdz;

--
-- Name: groups_comments_revisions_id_seq; Type: SEQUENCE; Schema: public; Owner: nerdz
--

CREATE SEQUENCE public.groups_comments_revisions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.groups_comments_revisions_id_seq OWNER TO nerdz;

--
-- Name: groups_comments_revisions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nerdz
--

ALTER SEQUENCE public.groups_comments_revisions_id_seq OWNED BY public.groups_comments_revisions.counter;


--
-- Name: groups_counter_seq; Type: SEQUENCE; Schema: public; Owner: nerdz
--

CREATE SEQUENCE public.groups_counter_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.groups_counter_seq OWNER TO nerdz;

--
-- Name: groups_counter_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nerdz
--

ALTER SEQUENCE public.groups_counter_seq OWNED BY public.groups.counter;


--
-- Name: groups_followers; Type: TABLE; Schema: public; Owner: nerdz
--

CREATE TABLE public.groups_followers (
    "to" bigint NOT NULL,
    "from" bigint NOT NULL,
    "time" timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    to_notify boolean DEFAULT true NOT NULL,
    counter bigint NOT NULL
);


ALTER TABLE public.groups_followers OWNER TO nerdz;

--
-- Name: groups_followers_id_seq; Type: SEQUENCE; Schema: public; Owner: nerdz
--

CREATE SEQUENCE public.groups_followers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.groups_followers_id_seq OWNER TO nerdz;

--
-- Name: groups_followers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nerdz
--

ALTER SEQUENCE public.groups_followers_id_seq OWNED BY public.groups_followers.counter;


--
-- Name: groups_lurkers; Type: TABLE; Schema: public; Owner: nerdz
--

CREATE TABLE public.groups_lurkers (
    "from" bigint NOT NULL,
    hpid bigint NOT NULL,
    "time" timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    "to" bigint NOT NULL,
    counter bigint NOT NULL
);


ALTER TABLE public.groups_lurkers OWNER TO nerdz;

--
-- Name: groups_lurkers_id_seq; Type: SEQUENCE; Schema: public; Owner: nerdz
--

CREATE SEQUENCE public.groups_lurkers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.groups_lurkers_id_seq OWNER TO nerdz;

--
-- Name: groups_lurkers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nerdz
--

ALTER SEQUENCE public.groups_lurkers_id_seq OWNED BY public.groups_lurkers.counter;


--
-- Name: groups_members; Type: TABLE; Schema: public; Owner: nerdz
--

CREATE TABLE public.groups_members (
    "to" bigint NOT NULL,
    "from" bigint NOT NULL,
    "time" timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    to_notify boolean DEFAULT true NOT NULL,
    counter bigint NOT NULL
);


ALTER TABLE public.groups_members OWNER TO nerdz;

--
-- Name: groups_members_id_seq; Type: SEQUENCE; Schema: public; Owner: nerdz
--

CREATE SEQUENCE public.groups_members_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.groups_members_id_seq OWNER TO nerdz;

--
-- Name: groups_members_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nerdz
--

ALTER SEQUENCE public.groups_members_id_seq OWNED BY public.groups_members.counter;


--
-- Name: groups_notify; Type: TABLE; Schema: public; Owner: nerdz
--

CREATE TABLE public.groups_notify (
    "from" bigint NOT NULL,
    "to" bigint NOT NULL,
    "time" timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    hpid bigint NOT NULL,
    counter bigint NOT NULL,
    to_notify boolean DEFAULT true NOT NULL
);


ALTER TABLE public.groups_notify OWNER TO nerdz;

--
-- Name: groups_notify_id_seq; Type: SEQUENCE; Schema: public; Owner: nerdz
--

CREATE SEQUENCE public.groups_notify_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.groups_notify_id_seq OWNER TO nerdz;

--
-- Name: groups_notify_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nerdz
--

ALTER SEQUENCE public.groups_notify_id_seq OWNED BY public.groups_notify.counter;


--
-- Name: groups_owners; Type: TABLE; Schema: public; Owner: nerdz
--

CREATE TABLE public.groups_owners (
    "to" bigint NOT NULL,
    "from" bigint NOT NULL,
    "time" timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    to_notify boolean DEFAULT false NOT NULL,
    counter bigint NOT NULL
);


ALTER TABLE public.groups_owners OWNER TO nerdz;

--
-- Name: groups_owners_id_seq; Type: SEQUENCE; Schema: public; Owner: nerdz
--

CREATE SEQUENCE public.groups_owners_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.groups_owners_id_seq OWNER TO nerdz;

--
-- Name: groups_owners_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nerdz
--

ALTER SEQUENCE public.groups_owners_id_seq OWNED BY public.groups_owners.counter;


--
-- Name: groups_posts; Type: TABLE; Schema: public; Owner: nerdz
--

CREATE TABLE public.groups_posts (
    hpid bigint NOT NULL,
    "from" bigint NOT NULL,
    "to" bigint NOT NULL,
    pid bigint NOT NULL,
    message text NOT NULL,
    "time" timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    news boolean DEFAULT false NOT NULL,
    lang character varying(2) DEFAULT 'en'::character varying NOT NULL,
    closed boolean DEFAULT false NOT NULL
);


ALTER TABLE public.groups_posts OWNER TO nerdz;

--
-- Name: groups_posts_hpid_seq; Type: SEQUENCE; Schema: public; Owner: nerdz
--

CREATE SEQUENCE public.groups_posts_hpid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.groups_posts_hpid_seq OWNER TO nerdz;

--
-- Name: groups_posts_hpid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nerdz
--

ALTER SEQUENCE public.groups_posts_hpid_seq OWNED BY public.groups_posts.hpid;


--
-- Name: groups_posts_no_notify; Type: TABLE; Schema: public; Owner: nerdz
--

CREATE TABLE public.groups_posts_no_notify (
    "user" bigint NOT NULL,
    hpid bigint NOT NULL,
    "time" timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    counter bigint NOT NULL
);


ALTER TABLE public.groups_posts_no_notify OWNER TO nerdz;

--
-- Name: groups_posts_no_notify_id_seq; Type: SEQUENCE; Schema: public; Owner: nerdz
--

CREATE SEQUENCE public.groups_posts_no_notify_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.groups_posts_no_notify_id_seq OWNER TO nerdz;

--
-- Name: groups_posts_no_notify_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nerdz
--

ALTER SEQUENCE public.groups_posts_no_notify_id_seq OWNED BY public.groups_posts_no_notify.counter;


--
-- Name: groups_posts_revisions; Type: TABLE; Schema: public; Owner: nerdz
--

CREATE TABLE public.groups_posts_revisions (
    hpid bigint NOT NULL,
    message text NOT NULL,
    "time" timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    rev_no integer DEFAULT 0 NOT NULL,
    counter bigint NOT NULL
);


ALTER TABLE public.groups_posts_revisions OWNER TO nerdz;

--
-- Name: groups_posts_revisions_id_seq; Type: SEQUENCE; Schema: public; Owner: nerdz
--

CREATE SEQUENCE public.groups_posts_revisions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.groups_posts_revisions_id_seq OWNER TO nerdz;

--
-- Name: groups_posts_revisions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nerdz
--

ALTER SEQUENCE public.groups_posts_revisions_id_seq OWNED BY public.groups_posts_revisions.counter;


--
-- Name: groups_thumbs; Type: TABLE; Schema: public; Owner: nerdz
--

CREATE TABLE public.groups_thumbs (
    hpid bigint NOT NULL,
    "from" bigint NOT NULL,
    vote smallint NOT NULL,
    "time" timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    "to" bigint NOT NULL,
    counter bigint NOT NULL,
    CONSTRAINT chkgvote CHECK ((vote = ANY (ARRAY['-1'::integer, 0, 1])))
);


ALTER TABLE public.groups_thumbs OWNER TO nerdz;

--
-- Name: groups_thumbs_id_seq; Type: SEQUENCE; Schema: public; Owner: nerdz
--

CREATE SEQUENCE public.groups_thumbs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.groups_thumbs_id_seq OWNER TO nerdz;

--
-- Name: groups_thumbs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nerdz
--

ALTER SEQUENCE public.groups_thumbs_id_seq OWNED BY public.groups_thumbs.counter;


--
-- Name: guests; Type: TABLE; Schema: public; Owner: nerdz
--

CREATE TABLE public.guests (
    remote_addr inet NOT NULL,
    http_user_agent text NOT NULL,
    last timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);


ALTER TABLE public.guests OWNER TO nerdz;

--
-- Name: interests; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.interests (
    id bigint NOT NULL,
    "from" bigint NOT NULL,
    value character varying(90) NOT NULL,
    "time" timestamp without time zone DEFAULT timezone('utc'::text, now())
);


ALTER TABLE public.interests OWNER TO postgres;

--
-- Name: interests_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.interests_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.interests_id_seq OWNER TO postgres;

--
-- Name: interests_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.interests_id_seq OWNED BY public.interests.id;


--
-- Name: lurkers; Type: TABLE; Schema: public; Owner: nerdz
--

CREATE TABLE public.lurkers (
    "from" bigint NOT NULL,
    hpid bigint NOT NULL,
    "time" timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    "to" bigint NOT NULL,
    counter bigint NOT NULL
);


ALTER TABLE public.lurkers OWNER TO nerdz;

--
-- Name: lurkers_id_seq; Type: SEQUENCE; Schema: public; Owner: nerdz
--

CREATE SEQUENCE public.lurkers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.lurkers_id_seq OWNER TO nerdz;

--
-- Name: lurkers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nerdz
--

ALTER SEQUENCE public.lurkers_id_seq OWNED BY public.lurkers.counter;


--
-- Name: mentions; Type: TABLE; Schema: public; Owner: nerdz
--

CREATE TABLE public.mentions (
    id bigint NOT NULL,
    u_hpid bigint,
    g_hpid bigint,
    "from" bigint NOT NULL,
    "to" bigint NOT NULL,
    "time" timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    to_notify boolean DEFAULT true NOT NULL,
    CONSTRAINT mentions_check CHECK (((u_hpid IS NOT NULL) OR (g_hpid IS NOT NULL)))
);


ALTER TABLE public.mentions OWNER TO nerdz;

--
-- Name: mentions_id_seq; Type: SEQUENCE; Schema: public; Owner: nerdz
--

CREATE SEQUENCE public.mentions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.mentions_id_seq OWNER TO nerdz;

--
-- Name: mentions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nerdz
--

ALTER SEQUENCE public.mentions_id_seq OWNED BY public.mentions.id;


--
-- Name: posts; Type: TABLE; Schema: public; Owner: nerdz
--

CREATE TABLE public.posts (
    hpid bigint NOT NULL,
    "from" bigint NOT NULL,
    "to" bigint NOT NULL,
    pid bigint NOT NULL,
    message text NOT NULL,
    "time" timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    lang character varying(2) DEFAULT 'en'::character varying NOT NULL,
    news boolean DEFAULT false NOT NULL,
    closed boolean DEFAULT false NOT NULL
);


ALTER TABLE public.posts OWNER TO nerdz;

--
-- Name: messages; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.messages AS
 SELECT groups_posts.hpid,
    groups_posts."from",
    groups_posts."to",
    groups_posts.pid,
    groups_posts.message,
    groups_posts."time",
    groups_posts.news,
    groups_posts.lang,
    groups_posts.closed,
    0 AS type
   FROM public.groups_posts
UNION ALL
 SELECT posts.hpid,
    posts."from",
    posts."to",
    posts.pid,
    posts.message,
    posts."time",
    posts.news,
    posts.lang,
    posts.closed,
    1 AS type
   FROM public.posts;


ALTER TABLE public.messages OWNER TO postgres;

--
-- Name: oauth2_access; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.oauth2_access (
    id bigint NOT NULL,
    client_id bigint NOT NULL,
    access_token text NOT NULL,
    created_at timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    expires_in bigint NOT NULL,
    redirect_uri character varying(350) NOT NULL,
    oauth2_authorize_id bigint,
    oauth2_access_id bigint,
    refresh_token_id bigint,
    scope text NOT NULL,
    user_id bigint NOT NULL
);


ALTER TABLE public.oauth2_access OWNER TO postgres;

--
-- Name: oauth2_access_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.oauth2_access_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.oauth2_access_id_seq OWNER TO postgres;

--
-- Name: oauth2_access_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.oauth2_access_id_seq OWNED BY public.oauth2_access.id;


--
-- Name: oauth2_authorize; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.oauth2_authorize (
    id bigint NOT NULL,
    code text NOT NULL,
    client_id bigint NOT NULL,
    created_at timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    expires_in bigint NOT NULL,
    scope text NOT NULL,
    redirect_uri character varying(350) NOT NULL,
    user_id bigint NOT NULL
);


ALTER TABLE public.oauth2_authorize OWNER TO postgres;

--
-- Name: oauth2_authorize_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.oauth2_authorize_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.oauth2_authorize_id_seq OWNER TO postgres;

--
-- Name: oauth2_authorize_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.oauth2_authorize_id_seq OWNED BY public.oauth2_authorize.id;


--
-- Name: oauth2_clients; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.oauth2_clients (
    id bigint NOT NULL,
    name character varying(100) NOT NULL,
    description text DEFAULT ''::text NOT NULL,
    scope text NOT NULL,
    secret text NOT NULL,
    redirect_uri character varying(350) NOT NULL,
    user_id bigint NOT NULL
);


ALTER TABLE public.oauth2_clients OWNER TO postgres;

--
-- Name: oauth2_clients_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.oauth2_clients_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.oauth2_clients_id_seq OWNER TO postgres;

--
-- Name: oauth2_clients_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.oauth2_clients_id_seq OWNED BY public.oauth2_clients.id;


--
-- Name: oauth2_refresh; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.oauth2_refresh (
    id bigint NOT NULL,
    token text NOT NULL
);


ALTER TABLE public.oauth2_refresh OWNER TO postgres;

--
-- Name: oauth2_refresh_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.oauth2_refresh_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.oauth2_refresh_id_seq OWNER TO postgres;

--
-- Name: oauth2_refresh_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.oauth2_refresh_id_seq OWNED BY public.oauth2_refresh.id;


--
-- Name: pms; Type: TABLE; Schema: public; Owner: nerdz
--

CREATE TABLE public.pms (
    "from" bigint NOT NULL,
    "to" bigint NOT NULL,
    "time" timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    message text NOT NULL,
    to_read boolean DEFAULT true NOT NULL,
    pmid bigint NOT NULL,
    lang character varying(2) DEFAULT 'en'::character varying NOT NULL
);


ALTER TABLE public.pms OWNER TO nerdz;

--
-- Name: pms_pmid_seq; Type: SEQUENCE; Schema: public; Owner: nerdz
--

CREATE SEQUENCE public.pms_pmid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.pms_pmid_seq OWNER TO nerdz;

--
-- Name: pms_pmid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nerdz
--

ALTER SEQUENCE public.pms_pmid_seq OWNED BY public.pms.pmid;


--
-- Name: posts_classification; Type: TABLE; Schema: public; Owner: nerdz
--

CREATE TABLE public.posts_classification (
    id bigint NOT NULL,
    u_hpid bigint,
    g_hpid bigint,
    tag character varying(45) NOT NULL,
    "from" bigint,
    "time" timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    CONSTRAINT posts_classification_check CHECK (((u_hpid IS NOT NULL) OR (g_hpid IS NOT NULL)))
);


ALTER TABLE public.posts_classification OWNER TO nerdz;

--
-- Name: posts_classification_id_seq; Type: SEQUENCE; Schema: public; Owner: nerdz
--

CREATE SEQUENCE public.posts_classification_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.posts_classification_id_seq OWNER TO nerdz;

--
-- Name: posts_classification_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nerdz
--

ALTER SEQUENCE public.posts_classification_id_seq OWNED BY public.posts_classification.id;


--
-- Name: posts_hpid_seq; Type: SEQUENCE; Schema: public; Owner: nerdz
--

CREATE SEQUENCE public.posts_hpid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.posts_hpid_seq OWNER TO nerdz;

--
-- Name: posts_hpid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nerdz
--

ALTER SEQUENCE public.posts_hpid_seq OWNED BY public.posts.hpid;


--
-- Name: posts_no_notify; Type: TABLE; Schema: public; Owner: nerdz
--

CREATE TABLE public.posts_no_notify (
    "user" bigint NOT NULL,
    hpid bigint NOT NULL,
    "time" timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    counter bigint NOT NULL
);


ALTER TABLE public.posts_no_notify OWNER TO nerdz;

--
-- Name: posts_no_notify_id_seq; Type: SEQUENCE; Schema: public; Owner: nerdz
--

CREATE SEQUENCE public.posts_no_notify_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.posts_no_notify_id_seq OWNER TO nerdz;

--
-- Name: posts_no_notify_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nerdz
--

ALTER SEQUENCE public.posts_no_notify_id_seq OWNED BY public.posts_no_notify.counter;


--
-- Name: posts_notify; Type: TABLE; Schema: public; Owner: nerdz
--

CREATE TABLE public.posts_notify (
    "from" bigint NOT NULL,
    "to" bigint NOT NULL,
    hpid bigint NOT NULL,
    "time" timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    counter bigint NOT NULL,
    to_notify boolean DEFAULT true NOT NULL
);


ALTER TABLE public.posts_notify OWNER TO nerdz;

--
-- Name: posts_notify_id_seq; Type: SEQUENCE; Schema: public; Owner: nerdz
--

CREATE SEQUENCE public.posts_notify_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.posts_notify_id_seq OWNER TO nerdz;

--
-- Name: posts_notify_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nerdz
--

ALTER SEQUENCE public.posts_notify_id_seq OWNED BY public.posts_notify.counter;


--
-- Name: posts_revisions; Type: TABLE; Schema: public; Owner: nerdz
--

CREATE TABLE public.posts_revisions (
    hpid bigint NOT NULL,
    message text NOT NULL,
    "time" timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    rev_no integer DEFAULT 0 NOT NULL,
    counter bigint NOT NULL
);


ALTER TABLE public.posts_revisions OWNER TO nerdz;

--
-- Name: posts_revisions_id_seq; Type: SEQUENCE; Schema: public; Owner: nerdz
--

CREATE SEQUENCE public.posts_revisions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.posts_revisions_id_seq OWNER TO nerdz;

--
-- Name: posts_revisions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nerdz
--

ALTER SEQUENCE public.posts_revisions_id_seq OWNED BY public.posts_revisions.counter;


--
-- Name: profiles; Type: TABLE; Schema: public; Owner: nerdz
--

CREATE TABLE public.profiles (
    counter bigint NOT NULL,
    website character varying(350) DEFAULT ''::character varying NOT NULL,
    quotes text DEFAULT ''::text NOT NULL,
    biography text DEFAULT ''::text NOT NULL,
    github character varying(350) DEFAULT ''::character varying NOT NULL,
    skype character varying(350) DEFAULT ''::character varying NOT NULL,
    jabber character varying(350) DEFAULT ''::character varying NOT NULL,
    yahoo character varying(350) DEFAULT ''::character varying NOT NULL,
    userscript character varying(128) DEFAULT ''::character varying NOT NULL,
    template smallint DEFAULT 0 NOT NULL,
    dateformat character varying(25) DEFAULT 'd/m/Y'::character varying NOT NULL,
    facebook character varying(350) DEFAULT ''::character varying NOT NULL,
    twitter character varying(350) DEFAULT ''::character varying NOT NULL,
    steam character varying(350) DEFAULT ''::character varying NOT NULL,
    push boolean DEFAULT false NOT NULL,
    pushregtime timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    mobile_template smallint DEFAULT 1 NOT NULL,
    closed boolean DEFAULT false NOT NULL,
    template_variables jsonb DEFAULT '{}'::json NOT NULL
);


ALTER TABLE public.profiles OWNER TO nerdz;

--
-- Name: reset_requests; Type: TABLE; Schema: public; Owner: nerdz
--

CREATE TABLE public.reset_requests (
    counter bigint NOT NULL,
    remote_addr inet NOT NULL,
    "time" timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    token character varying(32) NOT NULL,
    "to" bigint NOT NULL
);


ALTER TABLE public.reset_requests OWNER TO nerdz;

--
-- Name: reset_requests_counter_seq; Type: SEQUENCE; Schema: public; Owner: nerdz
--

CREATE SEQUENCE public.reset_requests_counter_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.reset_requests_counter_seq OWNER TO nerdz;

--
-- Name: reset_requests_counter_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nerdz
--

ALTER SEQUENCE public.reset_requests_counter_seq OWNED BY public.reset_requests.counter;


--
-- Name: searches; Type: TABLE; Schema: public; Owner: nerdz
--

CREATE TABLE public.searches (
    id bigint NOT NULL,
    "from" bigint NOT NULL,
    value character varying(90) NOT NULL,
    "time" timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);


ALTER TABLE public.searches OWNER TO nerdz;

--
-- Name: searches_id_seq; Type: SEQUENCE; Schema: public; Owner: nerdz
--

CREATE SEQUENCE public.searches_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.searches_id_seq OWNER TO nerdz;

--
-- Name: searches_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nerdz
--

ALTER SEQUENCE public.searches_id_seq OWNED BY public.searches.id;


--
-- Name: special_groups; Type: TABLE; Schema: public; Owner: nerdz
--

CREATE TABLE public.special_groups (
    role character varying(20) NOT NULL,
    counter bigint NOT NULL
);


ALTER TABLE public.special_groups OWNER TO nerdz;

--
-- Name: special_users; Type: TABLE; Schema: public; Owner: nerdz
--

CREATE TABLE public.special_users (
    role character varying(20) NOT NULL,
    counter bigint NOT NULL
);


ALTER TABLE public.special_users OWNER TO nerdz;

--
-- Name: thumbs; Type: TABLE; Schema: public; Owner: nerdz
--

CREATE TABLE public.thumbs (
    hpid bigint NOT NULL,
    "from" bigint NOT NULL,
    vote smallint NOT NULL,
    "time" timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    "to" bigint NOT NULL,
    counter bigint NOT NULL,
    CONSTRAINT chkvote CHECK ((vote = ANY (ARRAY['-1'::integer, 0, 1])))
);


ALTER TABLE public.thumbs OWNER TO nerdz;

--
-- Name: thumbs_id_seq; Type: SEQUENCE; Schema: public; Owner: nerdz
--

CREATE SEQUENCE public.thumbs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.thumbs_id_seq OWNER TO nerdz;

--
-- Name: thumbs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nerdz
--

ALTER SEQUENCE public.thumbs_id_seq OWNED BY public.thumbs.counter;


--
-- Name: users; Type: TABLE; Schema: public; Owner: nerdz
--

CREATE TABLE public.users (
    counter bigint NOT NULL,
    last timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    notify_story jsonb,
    private boolean DEFAULT false NOT NULL,
    lang character varying(2) DEFAULT 'en'::character varying NOT NULL,
    username character varying(90) NOT NULL,
    password character varying(60) NOT NULL,
    name character varying(60) NOT NULL,
    surname character varying(60) NOT NULL,
    email character varying(350) NOT NULL,
    birth_date date NOT NULL,
    board_lang character varying(2) DEFAULT 'en'::character varying NOT NULL,
    timezone character varying(35) DEFAULT 'UTC'::character varying NOT NULL,
    viewonline boolean DEFAULT true NOT NULL,
    remote_addr inet DEFAULT '127.0.0.1'::inet NOT NULL,
    http_user_agent text DEFAULT ''::text NOT NULL,
    registration_time timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);


ALTER TABLE public.users OWNER TO nerdz;

--
-- Name: users_counter_seq; Type: SEQUENCE; Schema: public; Owner: nerdz
--

CREATE SEQUENCE public.users_counter_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.users_counter_seq OWNER TO nerdz;

--
-- Name: users_counter_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nerdz
--

ALTER SEQUENCE public.users_counter_seq OWNED BY public.users.counter;


--
-- Name: whitelist; Type: TABLE; Schema: public; Owner: nerdz
--

CREATE TABLE public.whitelist (
    "from" bigint NOT NULL,
    "to" bigint NOT NULL,
    "time" timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    counter bigint NOT NULL
);


ALTER TABLE public.whitelist OWNER TO nerdz;

--
-- Name: whitelist_id_seq; Type: SEQUENCE; Schema: public; Owner: nerdz
--

CREATE SEQUENCE public.whitelist_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.whitelist_id_seq OWNER TO nerdz;

--
-- Name: whitelist_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nerdz
--

ALTER SEQUENCE public.whitelist_id_seq OWNED BY public.whitelist.counter;


--
-- Name: blacklist counter; Type: DEFAULT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.blacklist ALTER COLUMN counter SET DEFAULT nextval('public.blacklist_id_seq'::regclass);


--
-- Name: bookmarks counter; Type: DEFAULT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.bookmarks ALTER COLUMN counter SET DEFAULT nextval('public.bookmarks_id_seq'::regclass);


--
-- Name: comment_thumbs counter; Type: DEFAULT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.comment_thumbs ALTER COLUMN counter SET DEFAULT nextval('public.comment_thumbs_id_seq'::regclass);


--
-- Name: comments hcid; Type: DEFAULT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.comments ALTER COLUMN hcid SET DEFAULT nextval('public.comments_hcid_seq'::regclass);


--
-- Name: comments_no_notify counter; Type: DEFAULT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.comments_no_notify ALTER COLUMN counter SET DEFAULT nextval('public.comments_no_notify_id_seq'::regclass);


--
-- Name: comments_notify counter; Type: DEFAULT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.comments_notify ALTER COLUMN counter SET DEFAULT nextval('public.comments_notify_id_seq'::regclass);


--
-- Name: comments_revisions counter; Type: DEFAULT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.comments_revisions ALTER COLUMN counter SET DEFAULT nextval('public.comments_revisions_id_seq'::regclass);


--
-- Name: followers counter; Type: DEFAULT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.followers ALTER COLUMN counter SET DEFAULT nextval('public.followers_id_seq'::regclass);


--
-- Name: groups counter; Type: DEFAULT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups ALTER COLUMN counter SET DEFAULT nextval('public.groups_counter_seq'::regclass);


--
-- Name: groups_bookmarks counter; Type: DEFAULT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_bookmarks ALTER COLUMN counter SET DEFAULT nextval('public.groups_bookmarks_id_seq'::regclass);


--
-- Name: groups_comment_thumbs counter; Type: DEFAULT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_comment_thumbs ALTER COLUMN counter SET DEFAULT nextval('public.groups_comment_thumbs_id_seq'::regclass);


--
-- Name: groups_comments hcid; Type: DEFAULT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_comments ALTER COLUMN hcid SET DEFAULT nextval('public.groups_comments_hcid_seq'::regclass);


--
-- Name: groups_comments_no_notify counter; Type: DEFAULT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_comments_no_notify ALTER COLUMN counter SET DEFAULT nextval('public.groups_comments_no_notify_id_seq'::regclass);


--
-- Name: groups_comments_notify counter; Type: DEFAULT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_comments_notify ALTER COLUMN counter SET DEFAULT nextval('public.groups_comments_notify_id_seq'::regclass);


--
-- Name: groups_comments_revisions counter; Type: DEFAULT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_comments_revisions ALTER COLUMN counter SET DEFAULT nextval('public.groups_comments_revisions_id_seq'::regclass);


--
-- Name: groups_followers counter; Type: DEFAULT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_followers ALTER COLUMN counter SET DEFAULT nextval('public.groups_followers_id_seq'::regclass);


--
-- Name: groups_lurkers counter; Type: DEFAULT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_lurkers ALTER COLUMN counter SET DEFAULT nextval('public.groups_lurkers_id_seq'::regclass);


--
-- Name: groups_members counter; Type: DEFAULT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_members ALTER COLUMN counter SET DEFAULT nextval('public.groups_members_id_seq'::regclass);


--
-- Name: groups_notify counter; Type: DEFAULT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_notify ALTER COLUMN counter SET DEFAULT nextval('public.groups_notify_id_seq'::regclass);


--
-- Name: groups_owners counter; Type: DEFAULT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_owners ALTER COLUMN counter SET DEFAULT nextval('public.groups_owners_id_seq'::regclass);


--
-- Name: groups_posts hpid; Type: DEFAULT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_posts ALTER COLUMN hpid SET DEFAULT nextval('public.groups_posts_hpid_seq'::regclass);


--
-- Name: groups_posts_no_notify counter; Type: DEFAULT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_posts_no_notify ALTER COLUMN counter SET DEFAULT nextval('public.groups_posts_no_notify_id_seq'::regclass);


--
-- Name: groups_posts_revisions counter; Type: DEFAULT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_posts_revisions ALTER COLUMN counter SET DEFAULT nextval('public.groups_posts_revisions_id_seq'::regclass);


--
-- Name: groups_thumbs counter; Type: DEFAULT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_thumbs ALTER COLUMN counter SET DEFAULT nextval('public.groups_thumbs_id_seq'::regclass);


--
-- Name: interests id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.interests ALTER COLUMN id SET DEFAULT nextval('public.interests_id_seq'::regclass);


--
-- Name: lurkers counter; Type: DEFAULT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.lurkers ALTER COLUMN counter SET DEFAULT nextval('public.lurkers_id_seq'::regclass);


--
-- Name: mentions id; Type: DEFAULT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.mentions ALTER COLUMN id SET DEFAULT nextval('public.mentions_id_seq'::regclass);


--
-- Name: oauth2_access id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.oauth2_access ALTER COLUMN id SET DEFAULT nextval('public.oauth2_access_id_seq'::regclass);


--
-- Name: oauth2_authorize id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.oauth2_authorize ALTER COLUMN id SET DEFAULT nextval('public.oauth2_authorize_id_seq'::regclass);


--
-- Name: oauth2_clients id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.oauth2_clients ALTER COLUMN id SET DEFAULT nextval('public.oauth2_clients_id_seq'::regclass);


--
-- Name: oauth2_refresh id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.oauth2_refresh ALTER COLUMN id SET DEFAULT nextval('public.oauth2_refresh_id_seq'::regclass);


--
-- Name: pms pmid; Type: DEFAULT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.pms ALTER COLUMN pmid SET DEFAULT nextval('public.pms_pmid_seq'::regclass);


--
-- Name: posts hpid; Type: DEFAULT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.posts ALTER COLUMN hpid SET DEFAULT nextval('public.posts_hpid_seq'::regclass);


--
-- Name: posts_classification id; Type: DEFAULT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.posts_classification ALTER COLUMN id SET DEFAULT nextval('public.posts_classification_id_seq'::regclass);


--
-- Name: posts_no_notify counter; Type: DEFAULT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.posts_no_notify ALTER COLUMN counter SET DEFAULT nextval('public.posts_no_notify_id_seq'::regclass);


--
-- Name: posts_notify counter; Type: DEFAULT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.posts_notify ALTER COLUMN counter SET DEFAULT nextval('public.posts_notify_id_seq'::regclass);


--
-- Name: posts_revisions counter; Type: DEFAULT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.posts_revisions ALTER COLUMN counter SET DEFAULT nextval('public.posts_revisions_id_seq'::regclass);


--
-- Name: reset_requests counter; Type: DEFAULT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.reset_requests ALTER COLUMN counter SET DEFAULT nextval('public.reset_requests_counter_seq'::regclass);


--
-- Name: searches id; Type: DEFAULT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.searches ALTER COLUMN id SET DEFAULT nextval('public.searches_id_seq'::regclass);


--
-- Name: thumbs counter; Type: DEFAULT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.thumbs ALTER COLUMN counter SET DEFAULT nextval('public.thumbs_id_seq'::regclass);


--
-- Name: users counter; Type: DEFAULT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.users ALTER COLUMN counter SET DEFAULT nextval('public.users_counter_seq'::regclass);


--
-- Name: whitelist counter; Type: DEFAULT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.whitelist ALTER COLUMN counter SET DEFAULT nextval('public.whitelist_id_seq'::regclass);


--
-- Name: ban ban_pkey; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.ban
    ADD CONSTRAINT ban_pkey PRIMARY KEY ("user");


--
-- Name: blacklist blacklist_pkey; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.blacklist
    ADD CONSTRAINT blacklist_pkey PRIMARY KEY (counter);


--
-- Name: blacklist blacklist_unique_from_to; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.blacklist
    ADD CONSTRAINT blacklist_unique_from_to UNIQUE ("from", "to");


--
-- Name: bookmarks bookmarks_pkey; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.bookmarks
    ADD CONSTRAINT bookmarks_pkey PRIMARY KEY (counter);


--
-- Name: bookmarks bookmarks_unique_from_hpid; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.bookmarks
    ADD CONSTRAINT bookmarks_unique_from_hpid UNIQUE ("from", hpid);


--
-- Name: comment_thumbs comment_thumbs_pkey; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.comment_thumbs
    ADD CONSTRAINT comment_thumbs_pkey PRIMARY KEY (counter);


--
-- Name: comment_thumbs comment_thumbs_unique_hcid_from; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.comment_thumbs
    ADD CONSTRAINT comment_thumbs_unique_hcid_from UNIQUE (hcid, "from");


--
-- Name: comments_no_notify comments_no_notify_pkey; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.comments_no_notify
    ADD CONSTRAINT comments_no_notify_pkey PRIMARY KEY (counter);


--
-- Name: comments_no_notify comments_no_notify_unique_from_to_hpid; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.comments_no_notify
    ADD CONSTRAINT comments_no_notify_unique_from_to_hpid UNIQUE ("from", "to", hpid);


--
-- Name: comments_notify comments_notify_pkey; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.comments_notify
    ADD CONSTRAINT comments_notify_pkey PRIMARY KEY (counter);


--
-- Name: comments_notify comments_notify_unique_from_to_hpid; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.comments_notify
    ADD CONSTRAINT comments_notify_unique_from_to_hpid UNIQUE ("from", "to", hpid);


--
-- Name: comments comments_pkey; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT comments_pkey PRIMARY KEY (hcid);


--
-- Name: comments_revisions comments_revisions_pkey; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.comments_revisions
    ADD CONSTRAINT comments_revisions_pkey PRIMARY KEY (counter);


--
-- Name: comments_revisions comments_revisions_unique_hcid_rev_no; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.comments_revisions
    ADD CONSTRAINT comments_revisions_unique_hcid_rev_no UNIQUE (hcid, rev_no);


--
-- Name: deleted_users deleted_users_pkey; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.deleted_users
    ADD CONSTRAINT deleted_users_pkey PRIMARY KEY (counter);


--
-- Name: flood_limits flood_limits_pkey; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.flood_limits
    ADD CONSTRAINT flood_limits_pkey PRIMARY KEY (table_name);


--
-- Name: followers followers_pkey; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.followers
    ADD CONSTRAINT followers_pkey PRIMARY KEY (counter);


--
-- Name: followers followers_unique_from_to; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.followers
    ADD CONSTRAINT followers_unique_from_to UNIQUE ("from", "to");


--
-- Name: groups_bookmarks groups_bookmarks_pkey; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_bookmarks
    ADD CONSTRAINT groups_bookmarks_pkey PRIMARY KEY (counter);


--
-- Name: groups_bookmarks groups_bookmarks_unique_from_hpid; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_bookmarks
    ADD CONSTRAINT groups_bookmarks_unique_from_hpid UNIQUE ("from", hpid);


--
-- Name: groups_comment_thumbs groups_comment_thumbs_pkey; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_comment_thumbs
    ADD CONSTRAINT groups_comment_thumbs_pkey PRIMARY KEY (counter);


--
-- Name: groups_comment_thumbs groups_comment_thumbs_unique_hcid_from; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_comment_thumbs
    ADD CONSTRAINT groups_comment_thumbs_unique_hcid_from UNIQUE (hcid, "from");


--
-- Name: groups_comments_no_notify groups_comments_no_notify_pkey; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_comments_no_notify
    ADD CONSTRAINT groups_comments_no_notify_pkey PRIMARY KEY (counter);


--
-- Name: groups_comments_no_notify groups_comments_no_notify_unique_from_to_hpid; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_comments_no_notify
    ADD CONSTRAINT groups_comments_no_notify_unique_from_to_hpid UNIQUE ("from", "to", hpid);


--
-- Name: groups_comments_notify groups_comments_notify_pkey; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_comments_notify
    ADD CONSTRAINT groups_comments_notify_pkey PRIMARY KEY (counter);


--
-- Name: groups_comments_notify groups_comments_notify_unique_from_to_hpid; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_comments_notify
    ADD CONSTRAINT groups_comments_notify_unique_from_to_hpid UNIQUE ("from", "to", hpid);


--
-- Name: groups_comments groups_comments_pkey; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_comments
    ADD CONSTRAINT groups_comments_pkey PRIMARY KEY (hcid);


--
-- Name: groups_comments_revisions groups_comments_revisions_pkey; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_comments_revisions
    ADD CONSTRAINT groups_comments_revisions_pkey PRIMARY KEY (counter);


--
-- Name: groups_comments_revisions groups_comments_revisions_unique_hcid_rev_no; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_comments_revisions
    ADD CONSTRAINT groups_comments_revisions_unique_hcid_rev_no UNIQUE (hcid, rev_no);


--
-- Name: groups_followers groups_followers_pkey; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_followers
    ADD CONSTRAINT groups_followers_pkey PRIMARY KEY (counter);


--
-- Name: groups_followers groups_followers_unique_from_to; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_followers
    ADD CONSTRAINT groups_followers_unique_from_to UNIQUE ("from", "to");


--
-- Name: groups_lurkers groups_lurkers_pkey; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_lurkers
    ADD CONSTRAINT groups_lurkers_pkey PRIMARY KEY (counter);


--
-- Name: groups_lurkers groups_lurkers_unique_from_hpid; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_lurkers
    ADD CONSTRAINT groups_lurkers_unique_from_hpid UNIQUE ("from", hpid);


--
-- Name: groups_members groups_members_pkey; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_members
    ADD CONSTRAINT groups_members_pkey PRIMARY KEY (counter);


--
-- Name: groups_members groups_members_unique_from_to; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_members
    ADD CONSTRAINT groups_members_unique_from_to UNIQUE ("from", "to");


--
-- Name: groups_notify groups_notify_pkey; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_notify
    ADD CONSTRAINT groups_notify_pkey PRIMARY KEY (counter);


--
-- Name: groups_notify groups_notify_unique_from_to_hpid; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_notify
    ADD CONSTRAINT groups_notify_unique_from_to_hpid UNIQUE ("from", "to", hpid);


--
-- Name: groups_owners groups_owners_pkey; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_owners
    ADD CONSTRAINT groups_owners_pkey PRIMARY KEY (counter);


--
-- Name: groups_owners groups_owners_unique_from_to; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_owners
    ADD CONSTRAINT groups_owners_unique_from_to UNIQUE ("from", "to");


--
-- Name: groups groups_pkey; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups
    ADD CONSTRAINT groups_pkey PRIMARY KEY (counter);


--
-- Name: groups_posts_no_notify groups_posts_no_notify_pkey; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_posts_no_notify
    ADD CONSTRAINT groups_posts_no_notify_pkey PRIMARY KEY (counter);


--
-- Name: groups_posts_no_notify groups_posts_no_notify_unique_user_hpid; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_posts_no_notify
    ADD CONSTRAINT groups_posts_no_notify_unique_user_hpid UNIQUE ("user", hpid);


--
-- Name: groups_posts groups_posts_pkey; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_posts
    ADD CONSTRAINT groups_posts_pkey PRIMARY KEY (hpid);


--
-- Name: groups_posts_revisions groups_posts_revisions_pkey; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_posts_revisions
    ADD CONSTRAINT groups_posts_revisions_pkey PRIMARY KEY (counter);


--
-- Name: groups_posts_revisions groups_posts_revisions_unique_hpid_rev_no; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_posts_revisions
    ADD CONSTRAINT groups_posts_revisions_unique_hpid_rev_no UNIQUE (hpid, rev_no);


--
-- Name: groups_thumbs groups_thumbs_pkey; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_thumbs
    ADD CONSTRAINT groups_thumbs_pkey PRIMARY KEY (counter);


--
-- Name: groups_thumbs groups_thumbs_unique_from_hpid; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_thumbs
    ADD CONSTRAINT groups_thumbs_unique_from_hpid UNIQUE ("from", hpid);


--
-- Name: interests interests_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.interests
    ADD CONSTRAINT interests_pkey PRIMARY KEY (id);


--
-- Name: lurkers lurkers_pkey; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.lurkers
    ADD CONSTRAINT lurkers_pkey PRIMARY KEY (counter);


--
-- Name: lurkers lurkers_unique_from_hpid; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.lurkers
    ADD CONSTRAINT lurkers_unique_from_hpid UNIQUE ("from", hpid);


--
-- Name: mentions mentions_pkey; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.mentions
    ADD CONSTRAINT mentions_pkey PRIMARY KEY (id);


--
-- Name: oauth2_access oauth2_access_access_token_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.oauth2_access
    ADD CONSTRAINT oauth2_access_access_token_key UNIQUE (access_token);


--
-- Name: oauth2_access oauth2_access_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.oauth2_access
    ADD CONSTRAINT oauth2_access_pkey PRIMARY KEY (id);


--
-- Name: oauth2_authorize oauth2_authorize_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.oauth2_authorize
    ADD CONSTRAINT oauth2_authorize_code_key UNIQUE (code);


--
-- Name: oauth2_authorize oauth2_authorize_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.oauth2_authorize
    ADD CONSTRAINT oauth2_authorize_pkey PRIMARY KEY (id);


--
-- Name: oauth2_clients oauth2_clients_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.oauth2_clients
    ADD CONSTRAINT oauth2_clients_pkey PRIMARY KEY (id);


--
-- Name: oauth2_clients oauth2_clients_secret_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.oauth2_clients
    ADD CONSTRAINT oauth2_clients_secret_key UNIQUE (secret);


--
-- Name: oauth2_refresh oauth2_refresh_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.oauth2_refresh
    ADD CONSTRAINT oauth2_refresh_pkey PRIMARY KEY (id);


--
-- Name: oauth2_refresh oauth2_refresh_token_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.oauth2_refresh
    ADD CONSTRAINT oauth2_refresh_token_key UNIQUE (token);


--
-- Name: pms pms_pkey; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.pms
    ADD CONSTRAINT pms_pkey PRIMARY KEY (pmid);


--
-- Name: posts_classification posts_classification_pkey; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.posts_classification
    ADD CONSTRAINT posts_classification_pkey PRIMARY KEY (id);


--
-- Name: posts_no_notify posts_no_notify_pkey; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.posts_no_notify
    ADD CONSTRAINT posts_no_notify_pkey PRIMARY KEY (counter);


--
-- Name: posts_no_notify posts_no_notify_unique_user_hpid; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.posts_no_notify
    ADD CONSTRAINT posts_no_notify_unique_user_hpid UNIQUE ("user", hpid);


--
-- Name: posts_notify posts_notify_pkey; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.posts_notify
    ADD CONSTRAINT posts_notify_pkey PRIMARY KEY (counter);


--
-- Name: posts_notify posts_notify_unique_from_to_hpid; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.posts_notify
    ADD CONSTRAINT posts_notify_unique_from_to_hpid UNIQUE ("from", "to", hpid);


--
-- Name: posts posts_pkey; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_pkey PRIMARY KEY (hpid);


--
-- Name: posts_revisions posts_revisions_pkey; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.posts_revisions
    ADD CONSTRAINT posts_revisions_pkey PRIMARY KEY (counter);


--
-- Name: posts_revisions posts_revisions_unique_hpid_rev_no; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.posts_revisions
    ADD CONSTRAINT posts_revisions_unique_hpid_rev_no UNIQUE (hpid, rev_no);


--
-- Name: profiles profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_pkey PRIMARY KEY (counter);


--
-- Name: reset_requests reset_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.reset_requests
    ADD CONSTRAINT reset_requests_pkey PRIMARY KEY (counter);


--
-- Name: special_groups special_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.special_groups
    ADD CONSTRAINT special_groups_pkey PRIMARY KEY (role);


--
-- Name: special_users special_users_pkey; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.special_users
    ADD CONSTRAINT special_users_pkey PRIMARY KEY (role);


--
-- Name: thumbs thumbs_pkey; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.thumbs
    ADD CONSTRAINT thumbs_pkey PRIMARY KEY (counter);


--
-- Name: thumbs thumbs_unique_from_hpid; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.thumbs
    ADD CONSTRAINT thumbs_unique_from_hpid UNIQUE ("from", hpid);


--
-- Name: groups_posts uniquegroupspostpidhpid; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_posts
    ADD CONSTRAINT uniquegroupspostpidhpid UNIQUE (hpid, pid);


--
-- Name: posts uniquepostpidhpid; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT uniquepostpidhpid UNIQUE (hpid, pid);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (counter);


--
-- Name: whitelist whitelist_pkey; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.whitelist
    ADD CONSTRAINT whitelist_pkey PRIMARY KEY (counter);


--
-- Name: whitelist whitelist_unique_from_to; Type: CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.whitelist
    ADD CONSTRAINT whitelist_unique_from_to UNIQUE ("from", "to");


--
-- Name: blacklistTo; Type: INDEX; Schema: public; Owner: nerdz
--

CREATE INDEX "blacklistTo" ON public.blacklist USING btree ("to");


--
-- Name: cid; Type: INDEX; Schema: public; Owner: nerdz
--

CREATE INDEX cid ON public.comments USING btree (hpid);


--
-- Name: commentsTo; Type: INDEX; Schema: public; Owner: nerdz
--

CREATE INDEX "commentsTo" ON public.comments_notify USING btree ("to");


--
-- Name: fkdateformat; Type: INDEX; Schema: public; Owner: nerdz
--

CREATE INDEX fkdateformat ON public.profiles USING btree (dateformat);


--
-- Name: followTo; Type: INDEX; Schema: public; Owner: nerdz
--

CREATE INDEX "followTo" ON public.followers USING btree ("to", to_notify);


--
-- Name: gpid; Type: INDEX; Schema: public; Owner: nerdz
--

CREATE INDEX gpid ON public.groups_posts USING btree (pid, "to");


--
-- Name: groupscid; Type: INDEX; Schema: public; Owner: nerdz
--

CREATE INDEX groupscid ON public.groups_comments USING btree (hpid);


--
-- Name: groupsnto; Type: INDEX; Schema: public; Owner: nerdz
--

CREATE INDEX groupsnto ON public.groups_notify USING btree ("to");


--
-- Name: mentions_to_to_notify_idx; Type: INDEX; Schema: public; Owner: nerdz
--

CREATE INDEX mentions_to_to_notify_idx ON public.mentions USING btree ("to", to_notify);


--
-- Name: pid; Type: INDEX; Schema: public; Owner: nerdz
--

CREATE INDEX pid ON public.posts USING btree (pid, "to");


--
-- Name: posts_classification_lower_idx; Type: INDEX; Schema: public; Owner: nerdz
--

CREATE INDEX posts_classification_lower_idx ON public.posts_classification USING btree (lower((tag)::text));


--
-- Name: unique_intersest_from_value; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX unique_intersest_from_value ON public.interests USING btree ("from", lower((value)::text));


--
-- Name: unique_oauth2_clients_name; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX unique_oauth2_clients_name ON public.oauth2_clients USING btree (lower((name)::text));


--
-- Name: uniquemail; Type: INDEX; Schema: public; Owner: nerdz
--

CREATE UNIQUE INDEX uniquemail ON public.users USING btree (lower((email)::text));


--
-- Name: uniqueusername; Type: INDEX; Schema: public; Owner: nerdz
--

CREATE UNIQUE INDEX uniqueusername ON public.users USING btree (lower((username)::text));


--
-- Name: whitelistTo; Type: INDEX; Schema: public; Owner: nerdz
--

CREATE INDEX "whitelistTo" ON public.whitelist USING btree ("to");


--
-- Name: blacklist after_delete_blacklist; Type: TRIGGER; Schema: public; Owner: nerdz
--

CREATE TRIGGER after_delete_blacklist AFTER DELETE ON public.blacklist FOR EACH ROW EXECUTE FUNCTION public.after_delete_blacklist();


--
-- Name: users after_delete_user; Type: TRIGGER; Schema: public; Owner: nerdz
--

CREATE TRIGGER after_delete_user AFTER DELETE ON public.users FOR EACH ROW EXECUTE FUNCTION public.after_delete_user();


--
-- Name: blacklist after_insert_blacklist; Type: TRIGGER; Schema: public; Owner: nerdz
--

CREATE TRIGGER after_insert_blacklist AFTER INSERT ON public.blacklist FOR EACH ROW EXECUTE FUNCTION public.after_insert_blacklist();


--
-- Name: comments after_insert_comment; Type: TRIGGER; Schema: public; Owner: nerdz
--

CREATE TRIGGER after_insert_comment AFTER INSERT ON public.comments FOR EACH ROW EXECUTE FUNCTION public.user_comment();


--
-- Name: comments_notify after_insert_comments_notify; Type: TRIGGER; Schema: public; Owner: nerdz
--

CREATE TRIGGER after_insert_comments_notify AFTER INSERT ON public.comments_notify FOR EACH ROW EXECUTE FUNCTION public.trigger_json_notification('user_comment');


--
-- Name: followers after_insert_followers; Type: TRIGGER; Schema: public; Owner: nerdz
--

CREATE TRIGGER after_insert_followers AFTER INSERT ON public.followers FOR EACH ROW EXECUTE FUNCTION public.trigger_json_notification('follower');


--
-- Name: groups_comments after_insert_group_comment; Type: TRIGGER; Schema: public; Owner: nerdz
--

CREATE TRIGGER after_insert_group_comment AFTER INSERT ON public.groups_comments FOR EACH ROW EXECUTE FUNCTION public.group_comment();


--
-- Name: groups_posts after_insert_group_post; Type: TRIGGER; Schema: public; Owner: nerdz
--

CREATE TRIGGER after_insert_group_post AFTER INSERT ON public.groups_posts FOR EACH ROW EXECUTE FUNCTION public.after_insert_group_post();


--
-- Name: groups_comments_notify after_insert_groups_comments_notify; Type: TRIGGER; Schema: public; Owner: nerdz
--

CREATE TRIGGER after_insert_groups_comments_notify AFTER INSERT ON public.groups_comments_notify FOR EACH ROW EXECUTE FUNCTION public.trigger_json_notification('project_comment');


--
-- Name: groups_followers after_insert_groups_followers; Type: TRIGGER; Schema: public; Owner: nerdz
--

CREATE TRIGGER after_insert_groups_followers AFTER INSERT ON public.groups_followers FOR EACH ROW EXECUTE FUNCTION public.trigger_json_notification('project_follower');


--
-- Name: groups_members after_insert_groups_members; Type: TRIGGER; Schema: public; Owner: nerdz
--

CREATE TRIGGER after_insert_groups_members AFTER INSERT ON public.groups_members FOR EACH ROW EXECUTE FUNCTION public.trigger_json_notification('project_member');


--
-- Name: groups_notify after_insert_groups_notify; Type: TRIGGER; Schema: public; Owner: nerdz
--

CREATE TRIGGER after_insert_groups_notify AFTER INSERT ON public.groups_notify FOR EACH ROW EXECUTE FUNCTION public.trigger_json_notification('project_post');


--
-- Name: groups_owners after_insert_groups_owners; Type: TRIGGER; Schema: public; Owner: nerdz
--

CREATE TRIGGER after_insert_groups_owners AFTER INSERT ON public.groups_owners FOR EACH ROW EXECUTE FUNCTION public.trigger_json_notification('project_owner');


--
-- Name: mentions after_insert_mentions_group; Type: TRIGGER; Schema: public; Owner: nerdz
--

CREATE TRIGGER after_insert_mentions_group AFTER INSERT ON public.mentions FOR EACH ROW WHEN ((new.g_hpid IS NOT NULL)) EXECUTE FUNCTION public.trigger_json_notification('project_mention');


--
-- Name: mentions after_insert_mentions_user; Type: TRIGGER; Schema: public; Owner: nerdz
--

CREATE TRIGGER after_insert_mentions_user AFTER INSERT ON public.mentions FOR EACH ROW WHEN ((new.g_hpid IS NULL)) EXECUTE FUNCTION public.trigger_json_notification('user_mention');


--
-- Name: pms after_insert_pms; Type: TRIGGER; Schema: public; Owner: nerdz
--

CREATE TRIGGER after_insert_pms AFTER INSERT ON public.pms FOR EACH ROW EXECUTE FUNCTION public.trigger_json_notification('pm');


--
-- Name: posts_notify after_insert_posts_notify; Type: TRIGGER; Schema: public; Owner: nerdz
--

CREATE TRIGGER after_insert_posts_notify AFTER INSERT ON public.posts_notify FOR EACH ROW EXECUTE FUNCTION public.trigger_json_notification('user_post');


--
-- Name: users after_insert_user; Type: TRIGGER; Schema: public; Owner: nerdz
--

CREATE TRIGGER after_insert_user AFTER INSERT ON public.users FOR EACH ROW EXECUTE FUNCTION public.after_insert_user();


--
-- Name: posts after_insert_user_post; Type: TRIGGER; Schema: public; Owner: nerdz
--

CREATE TRIGGER after_insert_user_post AFTER INSERT ON public.posts FOR EACH ROW EXECUTE FUNCTION public.after_insert_user_post();


--
-- Name: comments after_update_comment_message; Type: TRIGGER; Schema: public; Owner: nerdz
--

CREATE TRIGGER after_update_comment_message AFTER UPDATE ON public.comments FOR EACH ROW WHEN ((new.message <> old.message)) EXECUTE FUNCTION public.user_comment();


--
-- Name: groups_comments after_update_groups_comment_message; Type: TRIGGER; Schema: public; Owner: nerdz
--

CREATE TRIGGER after_update_groups_comment_message AFTER UPDATE ON public.groups_comments FOR EACH ROW WHEN ((new.message <> old.message)) EXECUTE FUNCTION public.group_comment();


--
-- Name: groups_posts after_update_groups_post_message; Type: TRIGGER; Schema: public; Owner: nerdz
--

CREATE TRIGGER after_update_groups_post_message AFTER UPDATE ON public.groups_posts FOR EACH ROW WHEN ((new.message <> old.message)) EXECUTE FUNCTION public.groups_post_update();


--
-- Name: posts after_update_post_message; Type: TRIGGER; Schema: public; Owner: nerdz
--

CREATE TRIGGER after_update_post_message AFTER UPDATE ON public.posts FOR EACH ROW WHEN ((new.message <> old.message)) EXECUTE FUNCTION public.post_update();


--
-- Name: users after_update_userame; Type: TRIGGER; Schema: public; Owner: nerdz
--

CREATE TRIGGER after_update_userame AFTER UPDATE ON public.users FOR EACH ROW WHEN (((old.username)::text <> (new.username)::text)) EXECUTE FUNCTION public.after_update_userame();


--
-- Name: users before_delete_user; Type: TRIGGER; Schema: public; Owner: nerdz
--

CREATE TRIGGER before_delete_user BEFORE DELETE ON public.users FOR EACH ROW EXECUTE FUNCTION public.before_delete_user();


--
-- Name: comments before_insert_comment; Type: TRIGGER; Schema: public; Owner: nerdz
--

CREATE TRIGGER before_insert_comment BEFORE INSERT ON public.comments FOR EACH ROW EXECUTE FUNCTION public.before_insert_comment();


--
-- Name: comment_thumbs before_insert_comment_thumb; Type: TRIGGER; Schema: public; Owner: nerdz
--

CREATE TRIGGER before_insert_comment_thumb BEFORE INSERT ON public.comment_thumbs FOR EACH ROW EXECUTE FUNCTION public.before_insert_comment_thumb();


--
-- Name: followers before_insert_follower; Type: TRIGGER; Schema: public; Owner: nerdz
--

CREATE TRIGGER before_insert_follower BEFORE INSERT ON public.followers FOR EACH ROW EXECUTE FUNCTION public.before_insert_follower();


--
-- Name: groups_posts before_insert_group_post; Type: TRIGGER; Schema: public; Owner: nerdz
--

CREATE TRIGGER before_insert_group_post BEFORE INSERT ON public.groups_posts FOR EACH ROW EXECUTE FUNCTION public.group_post_control();


--
-- Name: groups_lurkers before_insert_group_post_lurker; Type: TRIGGER; Schema: public; Owner: nerdz
--

CREATE TRIGGER before_insert_group_post_lurker BEFORE INSERT ON public.groups_lurkers FOR EACH ROW EXECUTE FUNCTION public.before_insert_group_post_lurker();


--
-- Name: groups_comments before_insert_groups_comment; Type: TRIGGER; Schema: public; Owner: nerdz
--

CREATE TRIGGER before_insert_groups_comment BEFORE INSERT ON public.groups_comments FOR EACH ROW EXECUTE FUNCTION public.before_insert_groups_comment();


--
-- Name: groups_comment_thumbs before_insert_groups_comment_thumb; Type: TRIGGER; Schema: public; Owner: nerdz
--

CREATE TRIGGER before_insert_groups_comment_thumb BEFORE INSERT ON public.groups_comment_thumbs FOR EACH ROW EXECUTE FUNCTION public.before_insert_groups_comment_thumb();


--
-- Name: groups_followers before_insert_groups_follower; Type: TRIGGER; Schema: public; Owner: nerdz
--

CREATE TRIGGER before_insert_groups_follower BEFORE INSERT ON public.groups_followers FOR EACH ROW EXECUTE FUNCTION public.before_insert_groups_follower();


--
-- Name: groups_members before_insert_groups_member; Type: TRIGGER; Schema: public; Owner: nerdz
--

CREATE TRIGGER before_insert_groups_member BEFORE INSERT ON public.groups_members FOR EACH ROW EXECUTE FUNCTION public.before_insert_groups_member();


--
-- Name: groups_thumbs before_insert_groups_thumb; Type: TRIGGER; Schema: public; Owner: nerdz
--

CREATE TRIGGER before_insert_groups_thumb BEFORE INSERT ON public.groups_thumbs FOR EACH ROW EXECUTE FUNCTION public.before_insert_groups_thumb();


--
-- Name: pms before_insert_pm; Type: TRIGGER; Schema: public; Owner: nerdz
--

CREATE TRIGGER before_insert_pm BEFORE INSERT ON public.pms FOR EACH ROW EXECUTE FUNCTION public.before_insert_pm();


--
-- Name: posts before_insert_post; Type: TRIGGER; Schema: public; Owner: nerdz
--

CREATE TRIGGER before_insert_post BEFORE INSERT ON public.posts FOR EACH ROW EXECUTE FUNCTION public.post_control();


--
-- Name: thumbs before_insert_thumb; Type: TRIGGER; Schema: public; Owner: nerdz
--

CREATE TRIGGER before_insert_thumb BEFORE INSERT ON public.thumbs FOR EACH ROW EXECUTE FUNCTION public.before_insert_thumb();


--
-- Name: lurkers before_insert_user_post_lurker; Type: TRIGGER; Schema: public; Owner: nerdz
--

CREATE TRIGGER before_insert_user_post_lurker BEFORE INSERT ON public.lurkers FOR EACH ROW EXECUTE FUNCTION public.before_insert_user_post_lurker();


--
-- Name: comments before_update_comment_message; Type: TRIGGER; Schema: public; Owner: nerdz
--

CREATE TRIGGER before_update_comment_message BEFORE UPDATE ON public.comments FOR EACH ROW WHEN ((new.message <> old.message)) EXECUTE FUNCTION public.user_comment_edit_control();


--
-- Name: groups_comments before_update_group_comment_message; Type: TRIGGER; Schema: public; Owner: nerdz
--

CREATE TRIGGER before_update_group_comment_message BEFORE UPDATE ON public.groups_comments FOR EACH ROW WHEN ((new.message <> old.message)) EXECUTE FUNCTION public.group_comment_edit_control();


--
-- Name: groups_posts before_update_group_post; Type: TRIGGER; Schema: public; Owner: nerdz
--

CREATE TRIGGER before_update_group_post BEFORE UPDATE ON public.groups_posts FOR EACH ROW WHEN ((new.message <> old.message)) EXECUTE FUNCTION public.group_post_control();


--
-- Name: posts before_update_post; Type: TRIGGER; Schema: public; Owner: nerdz
--

CREATE TRIGGER before_update_post BEFORE UPDATE ON public.posts FOR EACH ROW WHEN ((new.message <> old.message)) EXECUTE FUNCTION public.post_control();


--
-- Name: comments_revisions comments_revisions_hcid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.comments_revisions
    ADD CONSTRAINT comments_revisions_hcid_fkey FOREIGN KEY (hcid) REFERENCES public.comments(hcid) ON DELETE CASCADE;


--
-- Name: posts_no_notify destfkusers; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.posts_no_notify
    ADD CONSTRAINT destfkusers FOREIGN KEY ("user") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: groups_posts_no_notify destgrofkusers; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_posts_no_notify
    ADD CONSTRAINT destgrofkusers FOREIGN KEY ("user") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: ban fkbanned; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.ban
    ADD CONSTRAINT fkbanned FOREIGN KEY ("user") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: followers fkfromfol; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.followers
    ADD CONSTRAINT fkfromfol FOREIGN KEY ("from") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: groups_comments_notify fkfromnonot; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_comments_notify
    ADD CONSTRAINT fkfromnonot FOREIGN KEY ("from") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: groups_comments_notify fkfromnonotproj; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_comments_notify
    ADD CONSTRAINT fkfromnonotproj FOREIGN KEY ("to") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: groups_posts fkfromproj; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_posts
    ADD CONSTRAINT fkfromproj FOREIGN KEY ("from") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: groups_comments_no_notify fkfromprojnonot; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_comments_no_notify
    ADD CONSTRAINT fkfromprojnonot FOREIGN KEY ("from") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: blacklist fkfromusers; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.blacklist
    ADD CONSTRAINT fkfromusers FOREIGN KEY ("from") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: groups_comments fkfromusersp; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_comments
    ADD CONSTRAINT fkfromusersp FOREIGN KEY ("from") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: whitelist fkfromuserswl; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.whitelist
    ADD CONSTRAINT fkfromuserswl FOREIGN KEY ("from") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: profiles fkprofilesusers; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT fkprofilesusers FOREIGN KEY (counter) REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: followers fktofol; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.followers
    ADD CONSTRAINT fktofol FOREIGN KEY ("to") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: groups_posts fktoproj; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_posts
    ADD CONSTRAINT fktoproj FOREIGN KEY ("to") REFERENCES public.groups(counter) ON DELETE CASCADE;


--
-- Name: groups_comments fktoproject; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_comments
    ADD CONSTRAINT fktoproject FOREIGN KEY ("to") REFERENCES public.groups(counter) ON DELETE CASCADE;


--
-- Name: groups_comments_no_notify fktoprojnonot; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_comments_no_notify
    ADD CONSTRAINT fktoprojnonot FOREIGN KEY ("to") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: blacklist fktousers; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.blacklist
    ADD CONSTRAINT fktousers FOREIGN KEY ("to") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: whitelist fktouserswl; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.whitelist
    ADD CONSTRAINT fktouserswl FOREIGN KEY ("to") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: groups_posts_no_notify foregngrouphpid; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_posts_no_notify
    ADD CONSTRAINT foregngrouphpid FOREIGN KEY (hpid) REFERENCES public.groups_posts(hpid) ON DELETE CASCADE;


--
-- Name: comments foreignfromusers; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT foreignfromusers FOREIGN KEY ("from") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: posts_no_notify foreignhpid; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.posts_no_notify
    ADD CONSTRAINT foreignhpid FOREIGN KEY (hpid) REFERENCES public.posts(hpid) ON DELETE CASCADE;


--
-- Name: comments_notify foreignhpid; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.comments_notify
    ADD CONSTRAINT foreignhpid FOREIGN KEY (hpid) REFERENCES public.posts(hpid) ON DELETE CASCADE;


--
-- Name: posts foreignkfromusers; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT foreignkfromusers FOREIGN KEY ("from") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: posts foreignktousers; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT foreignktousers FOREIGN KEY ("to") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: comments foreigntousers; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT foreigntousers FOREIGN KEY ("to") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: comments_no_notify forhpid; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.comments_no_notify
    ADD CONSTRAINT forhpid FOREIGN KEY (hpid) REFERENCES public.posts(hpid) ON DELETE CASCADE;


--
-- Name: bookmarks forhpidbm; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.bookmarks
    ADD CONSTRAINT forhpidbm FOREIGN KEY (hpid) REFERENCES public.posts(hpid) ON DELETE CASCADE;


--
-- Name: groups_bookmarks forhpidbmgr; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_bookmarks
    ADD CONSTRAINT forhpidbmgr FOREIGN KEY (hpid) REFERENCES public.groups_posts(hpid) ON DELETE CASCADE;


--
-- Name: comments_no_notify forkeyfromusers; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.comments_no_notify
    ADD CONSTRAINT forkeyfromusers FOREIGN KEY ("from") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: bookmarks forkeyfromusersbmarks; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.bookmarks
    ADD CONSTRAINT forkeyfromusersbmarks FOREIGN KEY ("from") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: groups_bookmarks forkeyfromusersgrbmarks; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_bookmarks
    ADD CONSTRAINT forkeyfromusersgrbmarks FOREIGN KEY ("from") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: comments_no_notify forkeytousers; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.comments_no_notify
    ADD CONSTRAINT forkeytousers FOREIGN KEY ("to") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: comments_notify fornotfkeyfromusers; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.comments_notify
    ADD CONSTRAINT fornotfkeyfromusers FOREIGN KEY ("from") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: comments_notify fornotfkeytousers; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.comments_notify
    ADD CONSTRAINT fornotfkeytousers FOREIGN KEY ("to") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: pms fromrefus; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.pms
    ADD CONSTRAINT fromrefus FOREIGN KEY ("from") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: groups_notify grforkey; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_notify
    ADD CONSTRAINT grforkey FOREIGN KEY ("from") REFERENCES public.groups(counter) ON DELETE CASCADE;


--
-- Name: groups_members groupfkg; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_members
    ADD CONSTRAINT groupfkg FOREIGN KEY ("to") REFERENCES public.groups(counter) ON DELETE CASCADE;


--
-- Name: groups_followers groupfollofkg; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_followers
    ADD CONSTRAINT groupfollofkg FOREIGN KEY ("to") REFERENCES public.groups(counter) ON DELETE CASCADE;


--
-- Name: groups_comments_revisions groups_comments_revisions_hcid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_comments_revisions
    ADD CONSTRAINT groups_comments_revisions_hcid_fkey FOREIGN KEY (hcid) REFERENCES public.groups_comments(hcid) ON DELETE CASCADE;


--
-- Name: groups_notify groups_notify_hpid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_notify
    ADD CONSTRAINT groups_notify_hpid_fkey FOREIGN KEY (hpid) REFERENCES public.groups_posts(hpid) ON DELETE CASCADE;


--
-- Name: groups_owners groups_owners_from_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_owners
    ADD CONSTRAINT groups_owners_from_fkey FOREIGN KEY ("from") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: groups_owners groups_owners_to_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_owners
    ADD CONSTRAINT groups_owners_to_fkey FOREIGN KEY ("to") REFERENCES public.groups(counter) ON DELETE CASCADE;


--
-- Name: groups_posts_revisions groups_posts_revisions_hpid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_posts_revisions
    ADD CONSTRAINT groups_posts_revisions_hpid_fkey FOREIGN KEY (hpid) REFERENCES public.groups_posts(hpid) ON DELETE CASCADE;


--
-- Name: groups_comment_thumbs hcidgthumbs; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_comment_thumbs
    ADD CONSTRAINT hcidgthumbs FOREIGN KEY (hcid) REFERENCES public.groups_comments(hcid) ON DELETE CASCADE;


--
-- Name: comment_thumbs hcidthumbs; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.comment_thumbs
    ADD CONSTRAINT hcidthumbs FOREIGN KEY (hcid) REFERENCES public.comments(hcid) ON DELETE CASCADE;


--
-- Name: groups_thumbs hpidgthumbs; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_thumbs
    ADD CONSTRAINT hpidgthumbs FOREIGN KEY (hpid) REFERENCES public.groups_posts(hpid) ON DELETE CASCADE;


--
-- Name: groups_comments hpidproj; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_comments
    ADD CONSTRAINT hpidproj FOREIGN KEY (hpid) REFERENCES public.groups_posts(hpid) ON DELETE CASCADE;


--
-- Name: groups_comments_no_notify hpidprojnonot; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_comments_no_notify
    ADD CONSTRAINT hpidprojnonot FOREIGN KEY (hpid) REFERENCES public.groups_posts(hpid) ON DELETE CASCADE;


--
-- Name: comments hpidref; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT hpidref FOREIGN KEY (hpid) REFERENCES public.posts(hpid) ON DELETE CASCADE;


--
-- Name: thumbs hpidthumbs; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.thumbs
    ADD CONSTRAINT hpidthumbs FOREIGN KEY (hpid) REFERENCES public.posts(hpid) ON DELETE CASCADE;


--
-- Name: interests interests_from_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.interests
    ADD CONSTRAINT interests_from_fkey FOREIGN KEY ("from") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: mentions mentions_from_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.mentions
    ADD CONSTRAINT mentions_from_fkey FOREIGN KEY ("from") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: mentions mentions_g_hpid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.mentions
    ADD CONSTRAINT mentions_g_hpid_fkey FOREIGN KEY (g_hpid) REFERENCES public.groups_posts(hpid) ON DELETE CASCADE;


--
-- Name: mentions mentions_to_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.mentions
    ADD CONSTRAINT mentions_to_fkey FOREIGN KEY ("to") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: mentions mentions_u_hpid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.mentions
    ADD CONSTRAINT mentions_u_hpid_fkey FOREIGN KEY (u_hpid) REFERENCES public.posts(hpid) ON DELETE CASCADE;


--
-- Name: oauth2_access oauth2_access_client_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.oauth2_access
    ADD CONSTRAINT oauth2_access_client_id_fkey FOREIGN KEY (client_id) REFERENCES public.oauth2_clients(id) ON DELETE CASCADE;


--
-- Name: oauth2_access oauth2_access_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.oauth2_access
    ADD CONSTRAINT oauth2_access_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: oauth2_authorize oauth2_authorize_client_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.oauth2_authorize
    ADD CONSTRAINT oauth2_authorize_client_id_fkey FOREIGN KEY (client_id) REFERENCES public.oauth2_clients(id) ON DELETE CASCADE;


--
-- Name: oauth2_authorize oauth2_authorize_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.oauth2_authorize
    ADD CONSTRAINT oauth2_authorize_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: oauth2_clients oauth2_clients_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.oauth2_clients
    ADD CONSTRAINT oauth2_clients_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: posts_classification posts_classification_from_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.posts_classification
    ADD CONSTRAINT posts_classification_from_fkey FOREIGN KEY ("from") REFERENCES public.users(counter) ON DELETE SET NULL;


--
-- Name: posts_classification posts_classification_g_hpid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.posts_classification
    ADD CONSTRAINT posts_classification_g_hpid_fkey FOREIGN KEY (g_hpid) REFERENCES public.groups_posts(hpid) ON DELETE CASCADE;


--
-- Name: posts_classification posts_classification_u_hpid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.posts_classification
    ADD CONSTRAINT posts_classification_u_hpid_fkey FOREIGN KEY (u_hpid) REFERENCES public.posts(hpid) ON DELETE CASCADE;


--
-- Name: posts_notify posts_notify_from_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.posts_notify
    ADD CONSTRAINT posts_notify_from_fkey FOREIGN KEY ("from") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: posts_notify posts_notify_hpid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.posts_notify
    ADD CONSTRAINT posts_notify_hpid_fkey FOREIGN KEY (hpid) REFERENCES public.posts(hpid) ON DELETE CASCADE;


--
-- Name: posts_notify posts_notify_to_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.posts_notify
    ADD CONSTRAINT posts_notify_to_fkey FOREIGN KEY ("to") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: posts_revisions posts_revisions_hpid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.posts_revisions
    ADD CONSTRAINT posts_revisions_hpid_fkey FOREIGN KEY (hpid) REFERENCES public.posts(hpid) ON DELETE CASCADE;


--
-- Name: groups_lurkers refhipdgl; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_lurkers
    ADD CONSTRAINT refhipdgl FOREIGN KEY (hpid) REFERENCES public.groups_posts(hpid) ON DELETE CASCADE;


--
-- Name: lurkers refhipdl; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.lurkers
    ADD CONSTRAINT refhipdl FOREIGN KEY (hpid) REFERENCES public.posts(hpid) ON DELETE CASCADE;


--
-- Name: groups_comments_notify reftogroupshpid; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_comments_notify
    ADD CONSTRAINT reftogroupshpid FOREIGN KEY (hpid) REFERENCES public.groups_posts(hpid) ON DELETE CASCADE;


--
-- Name: groups_lurkers refusergl; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_lurkers
    ADD CONSTRAINT refusergl FOREIGN KEY ("from") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: lurkers refuserl; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.lurkers
    ADD CONSTRAINT refuserl FOREIGN KEY ("from") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: reset_requests reset_requests_to_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.reset_requests
    ADD CONSTRAINT reset_requests_to_fkey FOREIGN KEY ("to") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: searches searches_from_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.searches
    ADD CONSTRAINT searches_from_fkey FOREIGN KEY ("from") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: special_groups special_groups_counter_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.special_groups
    ADD CONSTRAINT special_groups_counter_fkey FOREIGN KEY (counter) REFERENCES public.groups(counter) ON DELETE CASCADE;


--
-- Name: special_users special_users_counter_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.special_users
    ADD CONSTRAINT special_users_counter_fkey FOREIGN KEY (counter) REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: comment_thumbs toCommentThumbFk; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.comment_thumbs
    ADD CONSTRAINT "toCommentThumbFk" FOREIGN KEY ("to") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: groups_comment_thumbs toGCommentThumbFk; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_comment_thumbs
    ADD CONSTRAINT "toGCommentThumbFk" FOREIGN KEY ("to") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: groups_lurkers toGLurkFk; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_lurkers
    ADD CONSTRAINT "toGLurkFk" FOREIGN KEY ("to") REFERENCES public.groups(counter) ON DELETE CASCADE;


--
-- Name: groups_thumbs toGThumbFk; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_thumbs
    ADD CONSTRAINT "toGThumbFk" FOREIGN KEY ("to") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: lurkers toLurkFk; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.lurkers
    ADD CONSTRAINT "toLurkFk" FOREIGN KEY ("to") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: thumbs toThumbFk; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.thumbs
    ADD CONSTRAINT "toThumbFk" FOREIGN KEY ("to") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: pms torefus; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.pms
    ADD CONSTRAINT torefus FOREIGN KEY ("to") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: groups_members userfkg; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_members
    ADD CONSTRAINT userfkg FOREIGN KEY ("from") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: groups_followers userfollofkg; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_followers
    ADD CONSTRAINT userfollofkg FOREIGN KEY ("from") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: groups_thumbs usergthumbs; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_thumbs
    ADD CONSTRAINT usergthumbs FOREIGN KEY ("from") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: groups_comment_thumbs usergthumbs; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_comment_thumbs
    ADD CONSTRAINT usergthumbs FOREIGN KEY ("from") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: thumbs userthumbs; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.thumbs
    ADD CONSTRAINT userthumbs FOREIGN KEY ("from") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: comment_thumbs userthumbs; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.comment_thumbs
    ADD CONSTRAINT userthumbs FOREIGN KEY ("from") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: groups_notify usetoforkey; Type: FK CONSTRAINT; Schema: public; Owner: nerdz
--

ALTER TABLE ONLY public.groups_notify
    ADD CONSTRAINT usetoforkey FOREIGN KEY ("to") REFERENCES public.users(counter) ON DELETE CASCADE;


--
-- Name: FUNCTION armor(bytea); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.armor(bytea) TO nerdz;


--
-- Name: FUNCTION armor(bytea, text[], text[]); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.armor(bytea, text[], text[]) TO nerdz;


--
-- Name: FUNCTION crypt(text, text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.crypt(text, text) TO nerdz;


--
-- Name: FUNCTION dearmor(text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.dearmor(text) TO nerdz;


--
-- Name: FUNCTION decrypt(bytea, bytea, text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.decrypt(bytea, bytea, text) TO nerdz;


--
-- Name: FUNCTION decrypt_iv(bytea, bytea, bytea, text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.decrypt_iv(bytea, bytea, bytea, text) TO nerdz;


--
-- Name: FUNCTION digest(bytea, text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.digest(bytea, text) TO nerdz;


--
-- Name: FUNCTION digest(text, text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.digest(text, text) TO nerdz;


--
-- Name: FUNCTION encrypt(bytea, bytea, text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.encrypt(bytea, bytea, text) TO nerdz;


--
-- Name: FUNCTION encrypt_iv(bytea, bytea, bytea, text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.encrypt_iv(bytea, bytea, bytea, text) TO nerdz;


--
-- Name: FUNCTION gen_random_bytes(integer); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.gen_random_bytes(integer) TO nerdz;


--
-- Name: FUNCTION gen_random_uuid(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.gen_random_uuid() TO nerdz;


--
-- Name: FUNCTION gen_salt(text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.gen_salt(text) TO nerdz;


--
-- Name: FUNCTION gen_salt(text, integer); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.gen_salt(text, integer) TO nerdz;


--
-- Name: FUNCTION hashtag(message text, hpid bigint, grp boolean, from_u bigint, m_time timestamp without time zone); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.hashtag(message text, hpid bigint, grp boolean, from_u bigint, m_time timestamp without time zone) TO nerdz;


--
-- Name: FUNCTION hmac(bytea, bytea, text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.hmac(bytea, bytea, text) TO nerdz;


--
-- Name: FUNCTION hmac(text, text, text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.hmac(text, text, text) TO nerdz;


--
-- Name: FUNCTION login(_username text, _pass text, OUT ret boolean); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.login(_username text, _pass text, OUT ret boolean) TO nerdz;


--
-- Name: FUNCTION pgp_armor_headers(text, OUT key text, OUT value text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.pgp_armor_headers(text, OUT key text, OUT value text) TO nerdz;


--
-- Name: FUNCTION pgp_key_id(bytea); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.pgp_key_id(bytea) TO nerdz;


--
-- Name: FUNCTION pgp_pub_decrypt(bytea, bytea); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.pgp_pub_decrypt(bytea, bytea) TO nerdz;


--
-- Name: FUNCTION pgp_pub_decrypt(bytea, bytea, text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.pgp_pub_decrypt(bytea, bytea, text) TO nerdz;


--
-- Name: FUNCTION pgp_pub_decrypt(bytea, bytea, text, text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.pgp_pub_decrypt(bytea, bytea, text, text) TO nerdz;


--
-- Name: FUNCTION pgp_pub_decrypt_bytea(bytea, bytea); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.pgp_pub_decrypt_bytea(bytea, bytea) TO nerdz;


--
-- Name: FUNCTION pgp_pub_decrypt_bytea(bytea, bytea, text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.pgp_pub_decrypt_bytea(bytea, bytea, text) TO nerdz;


--
-- Name: FUNCTION pgp_pub_decrypt_bytea(bytea, bytea, text, text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.pgp_pub_decrypt_bytea(bytea, bytea, text, text) TO nerdz;


--
-- Name: FUNCTION pgp_pub_encrypt(text, bytea); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.pgp_pub_encrypt(text, bytea) TO nerdz;


--
-- Name: FUNCTION pgp_pub_encrypt(text, bytea, text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.pgp_pub_encrypt(text, bytea, text) TO nerdz;


--
-- Name: FUNCTION pgp_pub_encrypt_bytea(bytea, bytea); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.pgp_pub_encrypt_bytea(bytea, bytea) TO nerdz;


--
-- Name: FUNCTION pgp_pub_encrypt_bytea(bytea, bytea, text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.pgp_pub_encrypt_bytea(bytea, bytea, text) TO nerdz;


--
-- Name: FUNCTION pgp_sym_decrypt(bytea, text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.pgp_sym_decrypt(bytea, text) TO nerdz;


--
-- Name: FUNCTION pgp_sym_decrypt(bytea, text, text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.pgp_sym_decrypt(bytea, text, text) TO nerdz;


--
-- Name: FUNCTION pgp_sym_decrypt_bytea(bytea, text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.pgp_sym_decrypt_bytea(bytea, text) TO nerdz;


--
-- Name: FUNCTION pgp_sym_decrypt_bytea(bytea, text, text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.pgp_sym_decrypt_bytea(bytea, text, text) TO nerdz;


--
-- Name: FUNCTION pgp_sym_encrypt(text, text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.pgp_sym_encrypt(text, text) TO nerdz;


--
-- Name: FUNCTION pgp_sym_encrypt(text, text, text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.pgp_sym_encrypt(text, text, text) TO nerdz;


--
-- Name: FUNCTION pgp_sym_encrypt_bytea(bytea, text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.pgp_sym_encrypt_bytea(bytea, text) TO nerdz;


--
-- Name: FUNCTION pgp_sym_encrypt_bytea(bytea, text, text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.pgp_sym_encrypt_bytea(bytea, text, text) TO nerdz;


--
-- Name: FUNCTION trigger_json_notification(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.trigger_json_notification() TO nerdz;


--
-- Name: TABLE interests; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.interests TO nerdz;


--
-- Name: SEQUENCE interests_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.interests_id_seq TO nerdz;


--
-- Name: TABLE messages; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.messages TO nerdz;


--
-- Name: TABLE oauth2_access; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.oauth2_access TO nerdz;


--
-- Name: SEQUENCE oauth2_access_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.oauth2_access_id_seq TO nerdz;


--
-- Name: TABLE oauth2_authorize; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.oauth2_authorize TO nerdz;


--
-- Name: SEQUENCE oauth2_authorize_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.oauth2_authorize_id_seq TO nerdz;


--
-- Name: TABLE oauth2_clients; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.oauth2_clients TO nerdz;


--
-- Name: SEQUENCE oauth2_clients_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.oauth2_clients_id_seq TO nerdz;


--
-- Name: TABLE oauth2_refresh; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.oauth2_refresh TO nerdz;


--
-- Name: SEQUENCE oauth2_refresh_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.oauth2_refresh_id_seq TO nerdz;


--
-- PostgreSQL database dump complete
--

