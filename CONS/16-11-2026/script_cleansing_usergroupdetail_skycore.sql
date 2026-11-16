-- INFORMATION : 
-- jira: [CMSN-21089]
-- ===========================================================


-- =====================================================================
-- SCRIPT CLEANSING USER GROUP v2 - SEKALI JALAN (ON GO)

-- NOTE: blok seluruh script di bawah dan jalankan dalam 1x execute.
--       Semua fase berjalan dalam 1 transaksi:
--       - semua berhasil  -> otomatis tersimpan
--       - ada yang error  -> SEMUA otomatis di-rollback
--       Di akhir ada pengecekan otomatis; kalau hasilnya tidak konsisten,
--       script sengaja di-error-kan supaya semua di-rollback.
--
-- Fase 1 : samakan usergroupcode di usergroupdetail dengan header
-- Fase 2 : hapus anggota yang user-nya tidak ada di tabel users (hanya group lob CONS)
-- Fase 3 : pindahkan anggota yang role-nya salah ke group yang benar
--          (hanya group lob CONS, tujuan juga group lob CONS)
-- Fase 4 : hitung ulang totalmember
-- Cek    : validasi hasil akhir

-- =====================================================================

DO $$
DECLARE
    c_prefix       constant text := '8UG-';
    c_digit        constant int  := 6;
    c_lob          constant text := 'CONS';
    v_jml_counter  int;
    v_counter      bigint;
    v_counter_awal bigint;
    v_max_kode     bigint;
    v_new_code     text;
    v_new_id       bigint;
    v_fase1        int := 0;
    v_fase2        int := 0;
    v_baru         int := 0;
    v_pindah       int := 0;
    v_hapus        int := 0;
    v_rencana      int := 0;
    v_multi        int := 0;
    v_fase4        int := 0;
    v_cek          int;
    r              record;
BEGIN

    -- =================================================================
    -- PERSIAPAN: validasi & kunci counter fiturid = 8
    -- =================================================================
    SELECT COUNT(*) INTO v_jml_counter
    FROM public.counterseq WHERE fiturid = 8;

    IF v_jml_counter <> 1 THEN
        RAISE EXCEPTION 'counterseq fiturid = 8 harus tepat 1 baris, ditemukan % baris', v_jml_counter;
    END IF;

    SELECT COALESCE(counter, 0) INTO v_counter
    FROM public.counterseq
    WHERE fiturid = 8
    FOR UPDATE;

    v_counter_awal := v_counter;


    -- =================================================================
    -- FASE 1: samakan usergroupcode di detail dengan header
    -- =================================================================
    UPDATE public.usergroupdetail d
    SET usergroupcode = h.usergroup_code
    FROM public.usergroupheader h
    WHERE h.usergroupheader_id = d.usergroupheader_id
        AND d.usergroupcode IS DISTINCT FROM h.usergroup_code;
    GET DIAGNOSTICS v_fase1 = ROW_COUNT;

    RAISE NOTICE 'Fase 1 | usergroupcode disamakan : % record', v_fase1;


    -- =================================================================
    -- FASE 2: hapus anggota yang user-nya tidak ada di tabel users
    --         (hanya group lob CONS)
    -- =================================================================
    DELETE FROM public.usergroupdetail d
    USING public.usergroupheader h
    WHERE h.usergroupheader_id = d.usergroupheader_id
        AND trim(h.lob) = c_lob
        AND NOT EXISTS (
            SELECT 1
            FROM public.users u
            WHERE u.usr_userid = d.userid
                AND u.prd_sgm_id = 3
                AND u.usr_status = true
        );

    GET DIAGNOSTICS v_fase2 = ROW_COUNT;

    RAISE NOTICE 'Fase 2 | user tidak ada di users  : % record dihapus', v_fase2;


    -- =================================================================
    -- FASE 3: pindahkan anggota yang salah role
    -- =================================================================

    -- Kalau sudah ada kode dengan angka > counter, mulai dari kode tertinggi
    SELECT MAX(substring(usergroup_code FROM '^8UG-(\d+)$')::bigint)
    INTO v_max_kode
    FROM public.usergroupheader;

    IF v_max_kode IS NOT NULL AND v_max_kode > v_counter THEN
        RAISE NOTICE 'Fase 3 | counter (%) < kode tertinggi (%), mulai dari %',
                        v_counter, v_max_kode, v_max_kode;
        v_counter := v_max_kode;
    END IF;

    -- 3.1 Kumpulkan anggota yang salah role (group asal lob CONS)
    DROP TABLE IF EXISTS tmp_wrong_members;
    CREATE TEMP TABLE tmp_wrong_members ON COMMIT DROP AS
    WITH
    origin AS (
        SELECT 
            h.usergroupheader_id,
            h.usergroup_code,
            trim(h.usergroup_name) AS name_key,
            h.usergrouptype,
            h.createddated
        FROM public.usergroupheader h
        WHERE h.usergrouptype IS NOT NULL
            AND COALESCE(h.isdeleted, false) = false
            AND NULLIF(trim(h.usergroup_name), '') IS NOT NULL
            AND trim(h.lob) = c_lob
    ),
    user_role_agg AS (
        SELECT 
            s.usr_userid,
            MIN(s.role_id)                                       AS target_role,
            COUNT(*)                                             AS jml_role,
            string_agg(s.role_id::text, ', ' ORDER BY s.role_id) AS all_roles
        FROM (
            SELECT DISTINCT usr_userid, role_id
            FROM public.usersegmentedrole
            WHERE role_id IS NOT NULL
        ) s
        GROUP BY s.usr_userid
    )
    SELECT 
        d.usergroupdetail_id,
        d.userid,
        o.usergroupheader_id AS origin_id,
        o.usergroup_code     AS origin_code,
        o.name_key,
        o.createddated       AS origin_created,
        ura.target_role,
        ura.jml_role,
        ura.all_roles
    FROM public.usergroupdetail d
    JOIN origin o
        ON o.usergroupheader_id = d.usergroupheader_id
    JOIN user_role_agg ura
        ON ura.usr_userid = d.userid
    WHERE NOT EXISTS (
        SELECT 1
        FROM public.usersegmentedrole x
        WHERE x.usr_userid = d.userid
            AND x.role_id    = o.usergrouptype
    );

    SELECT COUNT(*) INTO v_rencana FROM tmp_wrong_members;

    -- Info: user dengan lebih dari 1 role (dipindah memakai role terkecil)
    FOR r IN
        SELECT origin_code, userid, all_roles, target_role
        FROM tmp_wrong_members
        WHERE jml_role > 1
        ORDER BY origin_code, userid
    LOOP
        v_multi := v_multi + 1;
        RAISE NOTICE 'Fase 3 | multi role | group % | user % | role % -> pakai role %',
                        r.origin_code, r.userid, r.all_roles, r.target_role;
    END LOOP;

    -- 3.2 Tentukan group tujuan per kombinasi (nama trim + role),
    --     tujuan hanya dicari di group lob CONS
    DROP TABLE IF EXISTS tmp_target;
    CREATE TEMP TABLE tmp_target ON COMMIT DROP AS
    WITH
    kombinasi AS (
        SELECT DISTINCT ON (w.name_key, w.target_role)
            w.name_key,
            w.target_role,
            w.origin_id AS src_header_id
        FROM tmp_wrong_members w
        ORDER BY w.name_key, w.target_role,
                w.origin_created DESC NULLS LAST, w.origin_id DESC
    ),
    target_existing AS (
        SELECT DISTINCT ON (trim(h.usergroup_name), h.usergrouptype)
            trim(h.usergroup_name) AS name_key,
            h.usergrouptype        AS target_role,
            h.usergroupheader_id   AS target_id,
            h.usergroup_code       AS target_code
        FROM public.usergroupheader h
        WHERE COALESCE(h.isdeleted, false) = false
            AND h.usergrouptype IS NOT NULL
            AND NULLIF(trim(h.usergroup_name), '') IS NOT NULL
            AND trim(h.lob) = c_lob
        ORDER BY trim(h.usergroup_name), h.usergrouptype,
                    h.createddated DESC NULLS LAST, h.usergroupheader_id DESC
    )
    SELECT 
        k.name_key,
        k.target_role,
        k.src_header_id,
        te.target_id,
        te.target_code
    FROM kombinasi k
    LEFT JOIN target_existing te
        ON te.name_key    = k.name_key
        AND te.target_role = k.target_role;

    -- 3.3 Buat header baru untuk kombinasi yang belum punya tujuan
    FOR r IN
        SELECT name_key, target_role, src_header_id
        FROM tmp_target
        WHERE target_id IS NULL
        ORDER BY name_key, target_role
    LOOP
        LOOP
            v_counter := v_counter + 1;
            EXIT WHEN NOT EXISTS (
                SELECT 1 FROM public.usergroupheader
                WHERE usergroup_code ~ '^8UG-\d+$'
                    AND substring(usergroup_code FROM '^8UG-(\d+)$')::bigint = v_counter
            );
        END LOOP;

        v_new_code := c_prefix || LPAD(v_counter::text,
                                        GREATEST(c_digit, length(v_counter::text)),
                                        '0');

        INSERT INTO public.usergroupheader (
            usergroup_code, usergroup_name, usergroup_desc,
            createddated, createdby, modifieddated, modifiedby,
            isdeleted, status,
            approvalstatus, approvedby, approvaldated,
            usergrouptype, lob, tempid, totalmember, ismigration, finone_queue_name
        )
        SELECT
            v_new_code, 
            s.usergroup_name, 
            (
                SELECT 
                rl.rl_name FROM public."role" rl
                WHERE rl.rl_id = r.target_role LIMIT 1
            ),
            now(), 'SYS', NULL, NULL,
            s.isdeleted, s.status,
            'ACTIVE', 'SYS', now(),
            r.target_role, s.lob, NULL, 0, NULL, s.finone_queue_name
        FROM public.usergroupheader s
        WHERE s.usergroupheader_id = r.src_header_id
        RETURNING usergroupheader_id INTO v_new_id;

        UPDATE tmp_target
        SET target_id   = v_new_id,
            target_code = v_new_code
        WHERE name_key    = r.name_key
            AND target_role = r.target_role;

        v_baru := v_baru + 1;
        RAISE NOTICE 'Fase 3 | header baru | % | nama "%" | role % | id %',
                        v_new_code, r.name_key, r.target_role, v_new_id;
    END LOOP;

    -- 3.4 Tentukan aksi per record
    DROP TABLE IF EXISTS tmp_move;
    CREATE TEMP TABLE tmp_move ON COMMIT DROP AS
    SELECT 
        w.usergroupdetail_id,
        w.userid,
        t.target_id,
        t.target_code,
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM public.usergroupdetail d2
                WHERE d2.usergroupheader_id = t.target_id
                    AND d2.userid = w.userid
            ) THEN 'DELETE_SUDAH_ADA'
            WHEN row_number() OVER (
                PARTITION BY t.target_id, w.userid
                ORDER BY w.usergroupdetail_id
            ) > 1 THEN 'DELETE_DOBEL'
            ELSE 'UPDATE'
        END AS aksi
    FROM tmp_wrong_members w
    JOIN tmp_target t
        ON t.name_key    = w.name_key
        AND t.target_role = w.target_role;

    -- 3.5 Hapus record asal yang user-nya sudah ada / dobel di tujuan
    DELETE FROM public.usergroupdetail d
    USING tmp_move m
    WHERE d.usergroupdetail_id = m.usergroupdetail_id
        AND m.aksi <> 'UPDATE';
    GET DIAGNOSTICS v_hapus = ROW_COUNT;

    -- 3.6 Pindahkan record ke header tujuan
    UPDATE public.usergroupdetail d
    SET usergroupheader_id = m.target_id,
        usergroupcode      = m.target_code,
        tempid             = NULL
    FROM tmp_move m
    WHERE d.usergroupdetail_id = m.usergroupdetail_id
        AND m.aksi = 'UPDATE';
    GET DIAGNOSTICS v_pindah = ROW_COUNT;

    -- 3.7 Update counter (hanya kalau ada header baru)
    IF v_baru > 0 THEN
        UPDATE public.counterseq
        SET counter = v_counter
        WHERE fiturid = 8;
    END IF;

    RAISE NOTICE 'Fase 3 | dipindah (UPDATE)       : % record', v_pindah;
    RAISE NOTICE 'Fase 3 | dihapus (sudah ada/dobel): % record', v_hapus;
    RAISE NOTICE 'Fase 3 | header baru             : %', v_baru;
    RAISE NOTICE 'Fase 3 | user multi role         : %', v_multi;
    RAISE NOTICE 'Fase 3 | counter fiturid 8       : % -> %',
                    v_counter_awal, CASE WHEN v_baru > 0 THEN v_counter ELSE v_counter_awal END;


    -- =================================================================
    -- FASE 4: hitung ulang totalmember
    -- =================================================================
    DROP TABLE IF EXISTS tmp_member_count;
    CREATE TEMP TABLE tmp_member_count ON COMMIT DROP AS
    SELECT 
        d.usergroupheader_id,
        COUNT(*) AS actual_total
    FROM public.usergroupdetail d
    GROUP BY d.usergroupheader_id;

    ANALYZE tmp_member_count;

    DROP TABLE IF EXISTS tmp_header_update;
    CREATE TEMP TABLE tmp_header_update ON COMMIT DROP AS
    SELECT 
        h.usergroupheader_id,
        COALESCE(mc.actual_total, 0) AS new_total
    FROM public.usergroupheader h
    LEFT JOIN tmp_member_count mc
        ON mc.usergroupheader_id = h.usergroupheader_id
    WHERE h.totalmember IS DISTINCT FROM COALESCE(mc.actual_total, 0);

    ANALYZE tmp_header_update;

    UPDATE public.usergroupheader h
    SET totalmember = t.new_total
    FROM tmp_header_update t
    WHERE h.usergroupheader_id = t.usergroupheader_id;
    GET DIAGNOSTICS v_fase4 = ROW_COUNT;

    RAISE NOTICE 'Fase 4 | totalmember diupdate    : % header', v_fase4;


    -- =================================================================
    -- CEK AKHIR: kalau ada yang tidak konsisten -> error -> semua rollback
    -- =================================================================

    -- a. Jumlah record yang diproses fase 3 harus sama dengan rencana
    IF v_pindah + v_hapus <> v_rencana THEN
        RAISE EXCEPTION 'CEK GAGAL: fase 3 rencana % record, terproses % (pindah %, hapus %)',
                        v_rencana, v_pindah + v_hapus, v_pindah, v_hapus;
    END IF;

    -- b. Tidak boleh ada lagi anggota salah role di group aktif lob CONS
    SELECT COUNT(*) INTO v_cek
    FROM public.usergroupdetail d
    JOIN public.usergroupheader h
        ON h.usergroupheader_id = d.usergroupheader_id
    WHERE h.usergrouptype IS NOT NULL
        AND COALESCE(h.isdeleted, false) = false
        AND NULLIF(trim(h.usergroup_name), '') IS NOT NULL
        AND trim(h.lob) = c_lob
        AND EXISTS (
            SELECT 1 FROM public.usersegmentedrole x
            WHERE x.usr_userid = d.userid AND x.role_id IS NOT NULL
        )
        AND NOT EXISTS (
            SELECT 1 FROM public.usersegmentedrole x
            WHERE x.usr_userid = d.userid AND x.role_id = h.usergrouptype
        );
    IF v_cek > 0 THEN
        RAISE EXCEPTION 'CEK GAGAL: masih ada % anggota salah role', v_cek;
    END IF;

    -- c. Tidak boleh ada user dobel di group yang sama akibat pemindahan
    SELECT COUNT(*) INTO v_cek
    FROM (
        SELECT d.usergroupheader_id, d.userid
        FROM public.usergroupdetail d
        JOIN tmp_target t ON t.target_id = d.usergroupheader_id
        GROUP BY d.usergroupheader_id, d.userid
        HAVING COUNT(*) > 1
    ) x;
    IF v_cek > 0 THEN
        RAISE EXCEPTION 'CEK GAGAL: ada % user dobel di group tujuan', v_cek;
    END IF;

    -- d. totalmember harus sama dengan jumlah anggota sebenarnya
    SELECT COUNT(*) INTO v_cek
    FROM public.usergroupheader h
    LEFT JOIN (
        SELECT usergroupheader_id, COUNT(*) AS jml
        FROM public.usergroupdetail
        GROUP BY usergroupheader_id
    ) c ON c.usergroupheader_id = h.usergroupheader_id
    WHERE h.totalmember IS DISTINCT FROM COALESCE(c.jml, 0);
    IF v_cek > 0 THEN
        RAISE EXCEPTION 'CEK GAGAL: % header totalmember tidak sesuai', v_cek;
    END IF;

    RAISE NOTICE '======================================================';
    RAISE NOTICE 'SELESAI. Semua fase berhasil dan lolos pengecekan.';
    RAISE NOTICE '======================================================';
END $$;