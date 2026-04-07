create or replace PACKAGE BODY                     PKG_TEST_THUANLN_HCM AS

  PROCEDURE SP_CAPNHAT_THONGTIN_CUM_IDG (
    P_CLUSTER_ID          IN VARCHAR2,
    P_CLUSTER_NAME        IN VARCHAR2,
    P_RANCHER_CODE        IN VARCHAR2,
    P_RANCHER_NAME        IN VARCHAR2,
    P_RANCHER_TYPE        IN NUMBER,
    P_CLUSTER_DESC        IN VARCHAR2,
    P_REGION_ID           IN VARCHAR2,
    P_REGION_NAME         IN VARCHAR2,
    P_STATE               IN VARCHAR2,
    P_USED_PERCENT_PODS   IN NUMBER,
    P_USED_PERCENT_MEM    IN NUMBER,
    P_USED_PERCENT_CPU    IN NUMBER,
    P_ALLOCATABLE_CPU     IN NUMBER,
    P_ALLOCATABLE_MEM     IN NUMBER,
    P_USED_CPU            IN NUMBER,
    P_USED_MEM            IN NUMBER,
    P_LIMIT_CPU           IN NUMBER,
    P_LIMIT_MEM           IN NUMBER,
    P_SERVICE_TYPE_AVATAR IN VARCHAR2
) AS
    V_CUMHT_ID NUMBER; 
    V_OLD_ALLOC_CPU NUMBER(15,2);
    V_OLD_ALLOC_MEM NUMBER(15,2);
    V_OLD_USED_CPU NUMBER(15,2);
    V_OLD_USED_MEM NUMBER(15,2);
  BEGIN
     -- 1. Tìm khóa chính CUMHT_ID trên hệ thống dựa vào RANCHER_CODE của API truyền về
        BEGIN
            SELECT CUMHT_ID INTO V_CUMHT_ID 
            FROM CUMHT_IDG 
            WHERE RANCHER_CODE = P_RANCHER_CODE
            AND ROWNUM = 1;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                -- 2. Chèn Dữ liệu Master vào CUM_HT 
                INSERT INTO CUM_HT (
                    MA_CUMHT, TEN_CUMHT, MOTA, NGAY_CN, NGUOI_CN
                ) VALUES (
                    P_CLUSTER_ID, P_CLUSTER_NAME, P_CLUSTER_DESC, SYSDATE, 'apidongbo'
                ) RETURNING CUMHT_ID INTO V_CUMHT_ID; -- Lấy ID tự tăng đẩy ngược vào V_CUMHT_ID
                -- 3. Chèn Định danh IDG vào CUMHT_IDG
                INSERT INTO CUMHT_IDG (
                    CUMHT_ID, RANCHER_CODE, REGION_ID, NGAY_CN, NGUOI_CN
                ) VALUES (
                    V_CUMHT_ID, P_RANCHER_CODE, P_REGION_ID, SYSDATE, 'apidongbo'
                );
                -- 4. Chèn Chỉ số RAM/CPU vào Bảng NANGLUC_CUMHT
                INSERT INTO NANGLUC_CUMHT (
                    CUMHT_ID, 
                    SL_CORECPU_CP, SL_RAM_CP, SL_CORECPU_DC, SL_RAM_DC, 
                    NGAY_CN, NGUOI_CN
                ) VALUES (
                    V_CUMHT_ID, 
                    P_ALLOCATABLE_CPU, P_ALLOCATABLE_MEM, P_USED_CPU, P_USED_MEM, 
                    SYSDATE, 'apidongbo'
                );
                
                COMMIT;
                RETURN;
        END;
        -- ==========================================================
        --UPDATE CHO TRƯỜNG HỢP CỤM ĐÃ TỒN TẠI (NO_DATA_FOUND bị pass qua)
        -- ==========================================================
        -- 2. Cập nhật thông tin Master (CUM_HT)
        UPDATE CUM_HT
        SET MA_CUMHT = P_CLUSTER_ID,
            TEN_CUMHT = P_CLUSTER_NAME,
            MOTA = P_CLUSTER_DESC,
            NGAY_CN = SYSDATE
        WHERE CUMHT_ID = V_CUMHT_ID;
        -- 3. Cập nhật thông tin IDG (CUMHT_IDG)
        UPDATE CUMHT_IDG
        SET REGION_ID = P_REGION_ID,
            NGAY_CN = SYSDATE
        WHERE CUMHT_ID = V_CUMHT_ID;
        -- 4. Bóc tách & Cập nhật Bảng Năng Lực (NANGLUC_CUMHT)
        BEGIN
            -- Lọc ra giá trị CPU/RAM hiện tại
            SELECT SL_CORECPU_CP, SL_RAM_CP, SL_CORECPU_DC, SL_RAM_DC
            INTO V_OLD_ALLOC_CPU, V_OLD_ALLOC_MEM, V_OLD_USED_CPU, V_OLD_USED_MEM
            FROM NANGLUC_CUMHT
            WHERE CUMHT_ID = V_CUMHT_ID
            AND ROWNUM = 1;
            -- Ghi log lịch sử nếu có sự chênh lệch (Cấp thêm/Dọn bớt RAM CPU)
            IF (NVL(V_OLD_ALLOC_CPU, 0) != NVL(P_ALLOCATABLE_CPU, 0) OR
                NVL(V_OLD_ALLOC_MEM, 0) != NVL(P_ALLOCATABLE_MEM, 0) OR
                NVL(V_OLD_USED_CPU, 0) != NVL(P_USED_CPU, 0) OR
                NVL(V_OLD_USED_MEM, 0) != NVL(P_USED_MEM, 0)) THEN    
                NULL; 
                -- Anh đã comment đoạn Insert LICHSU_CAPPAT, sau này nếu bật lại thì bỏ chữ NULL; này đi nha
            END IF;
            -- Cập nhật Năng lực mới nhặt về từ API vào thay thế dữ liệu Cũ
            UPDATE NANGLUC_CUMHT
            SET SL_CORECPU_CP = P_ALLOCATABLE_CPU,
                SL_RAM_CP = P_ALLOCATABLE_MEM,
                SL_CORECPU_DC = P_USED_CPU,
                SL_RAM_DC = P_USED_MEM,
                NGAY_CN = SYSDATE
            WHERE CUMHT_ID = V_CUMHT_ID;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                -- Tạo record Năng Lực cho Cụm nếu trước đó ổng chưa từng khai báo dòng Năng Lực nào
                INSERT INTO NANGLUC_CUMHT (
                    CUMHT_ID, SL_CORECPU_CP, SL_RAM_CP, SL_CORECPU_DC, SL_RAM_DC, NGAY_CN
                ) VALUES (
                    V_CUMHT_ID, P_ALLOCATABLE_CPU, P_ALLOCATABLE_MEM, P_USED_CPU, P_USED_MEM, SYSDATE
                );
        END;
        
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE_APPLICATION_ERROR(-20001, 'Lỗi cập nhật Cụm hạ tầng IDG ERD: ' || SQLERRM);
  END SP_CAPNHAT_THONGTIN_CUM_IDG;
  
  PROCEDURE SP_LAY_DS_CUM_HT (
    P_RS OUT SYS_REFCURSOR
    )
    IS
    BEGIN
        OPEN P_RS FOR
            SELECT 
                C.MA_CUMHT AS CLUSTER_ID, 
                I.RANCHER_CODE
            FROM CUMHT_IDG I
            JOIN CUM_HT C ON I.CUMHT_ID = C.CUMHT_ID
            WHERE I.RANCHER_CODE IS NOT NULL;
            
    EXCEPTION
        WHEN OTHERS THEN
            RAISE_APPLICATION_ERROR(-20002, 'Lỗi lấy danh sách Cụm HT: ' || SQLERRM);
    END SP_LAY_DS_CUM_HT;
    
    PROCEDURE SP_KIEMTRA_THIETBI (
        P_IP_ADDRESS   IN  VARCHAR2,
        P_RESULT       OUT NUMBER
    )
    IS
        V_COUNT NUMBER;
    BEGIN
        -- Tìm IP lần lượt trong kho Máy Ảo và kho Thiết bị vật lý
        SELECT COUNT(*) INTO V_COUNT 
        FROM IP_MAYAO 
        WHERE API_NETWORK_IP = P_IP_ADDRESS;

        IF V_COUNT > 0 THEN
            P_RESULT := 1; -- Đã nhặt được thiết bị
        ELSE
            P_RESULT := 0; -- Ko thấy mặt mũi Server / VM này đâu
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            P_RESULT := 0; 
    END SP_KIEMTRA_THIETBI;
    
    PROCEDURE SP_CAPNHAT_LOAIDV_CUM (
        P_CLUSTER_ID     IN VARCHAR2, -- Mã cụm (dựa theo cluster_id Java quét về) = MA_CUMHT
        P_SERVICE_NAME   IN VARCHAR2  -- Tên service từ API (vd: "IDG API Gateway")
    ) IS
        V_CUMHT_ID      NUMBER; -- Khóa chính CUM_HT dạng số
        V_DICHVUHT_ID   VARCHAR2(50);
        V_TEN_DICHVU    VARCHAR2(255);
    BEGIN
        -- 1. Tìm ID Khóa chính dạng Số chuẩn của Cụm dựa trên chuỗi MA_CUMHT
        BEGIN
            SELECT CUMHT_ID INTO V_CUMHT_ID
            FROM CUM_HT
            WHERE MA_CUMHT = P_CLUSTER_ID 
              AND ROWNUM = 1;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                -- Không tìm thấy cụm gốc 
                RETURN;
        END;
        -- 2. So khớp Dữ liệu: Kiểm tra dịch vụ đã tồn tại trong bảng DICHVU_HT chưa?
        
        BEGIN
            SELECT DICHVUHT_ID, TEN_DICHVU 
            INTO V_DICHVUHT_ID, V_TEN_DICHVU
            FROM DICHVU_HT
            WHERE CUMHT_ID = V_CUMHT_ID 
              AND TEN_DICHVU = P_SERVICE_NAME
              AND ROWNUM = 1;  -- Chống ORA-01422 khi có dữ liệu trùng TEN_DICHVU
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                V_DICHVUHT_ID := NULL;
        END;
        -- 3. Ra quyết định (Cập nhật / Thêm mới)
        IF V_DICHVUHT_ID IS NULL THEN
            -- API có Dịch vụ mới nhưng Backend OneBSS thiếu -> THỰC HIỆN THÊM MỚI VÀO ONEBSS
            INSERT INTO DICHVU_HT (
                CUMHT_ID, TEN_DICHVU, NGAY_CN
            ) VALUES (
                V_CUMHT_ID, P_SERVICE_NAME, SYSDATE
            ) RETURNING DICHVUHT_ID INTO V_DICHVUHT_ID;
            
            -- THỰC HIỆN GHI LOG LỊCH SỬ THAY ĐỔI
            INSERT INTO LICHSU_CAPPHAT (
                CUMHT_ID, LOAI_DOITUONG, DOITUONG_ID, 
                GHICHU, MOTA, NGAY_CP, NGAY_CN
            ) VALUES (
                V_CUMHT_ID, 'DICHVU_HT', V_DICHVUHT_ID,
                'Backend tự động báo cấu hình thêm Service Type', P_SERVICE_NAME, SYSDATE, SYSDATE
            );
            
        ELSE
            -- Dịch vụ này đang có sẵn trên OneBSS khớp 100% với backend IDG -> Cập nhật Timestamp
            UPDATE DICHVU_HT
            SET NGAY_CN = SYSDATE
            WHERE DICHVUHT_ID = V_DICHVUHT_ID;
        END IF;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE_APPLICATION_ERROR(-20005, 'Lỗi đồng bộ Dịch vụ Service Types: ' || SQLERRM);
    END SP_CAPNHAT_LOAIDV_CUM;
    
    PROCEDURE SP_GHI_LOG_LOI (
        P_CLUSTER_ID   IN  VARCHAR2, -- Mã cụm (Chính là MA_CUMHT)
        P_IP_ADDRESS   IN  VARCHAR2, -- IP lỗi không tìm thấy
        P_ERROR_MSG    IN  VARCHAR2  -- Chi tiết câu báo lỗi
    )
    IS
        -- Khai báo giao dịch độc lập để chống Rollback mất dòng Log
        PRAGMA AUTONOMOUS_TRANSACTION;
        
        V_CUMHT_ID NUMBER; 
    BEGIN
        -- 1. Tìm khóa chính CUMHT_ID từ MA_CUMHT
        BEGIN
            SELECT CUMHT_ID INTO V_CUMHT_ID
            FROM CUM_HT
            WHERE MA_CUMHT = P_CLUSTER_ID 
              AND ROWNUM = 1;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                V_CUMHT_ID := NULL;
        END;
        -- 2. Đổ dữ liệu vào bảng Log lỗi. 
        /*
        INSERT INTO LOG_LOI_DONGBO_IDG (
            LOG_ID,
            CUMHT_ID, 
            MA_CUMHT, 
            IP_ADDRESS, 
            NOI_DUNG_LOI, 
            NGAY_GHI_NHAN
        ) VALUES (
            SEQ_LOG_LOI_IDG.NEXTVAL, -- Id tự tăng (Có thể bỏ nếu cột là Identity sinh tự động)
            V_CUMHT_ID,
            P_CLUSTER_ID,
            P_IP_ADDRESS,
            P_ERROR_MSG,
            SYSDATE
        );
        */
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            NULL;
    END SP_GHI_LOG_LOI;
    
    PROCEDURE SP_CAPNHAT_DICHVU_CAPPAT (
        P_CLUSTER_ID   IN VARCHAR2, -- MA_CUMHT (vd: "local") - KHÔNG phải số CUMHT_ID
        P_SERVICE_NAME IN VARCHAR2,
        P_ORDER_CODE   IN VARCHAR2,
        P_VCPU         IN VARCHAR2,
        P_VRAM         IN VARCHAR2,
        P_VSTORAGE     IN VARCHAR2,
        P_STATUS       IN VARCHAR2,
        P_TIMESTAMP    IN VARCHAR2
    ) IS
        v_cumht_id    NUMBER;       -- [SỬA] Tra cứu CUMHT_ID thực từ MA_CUMHT
        v_dvht_id     NUMBER;
        v_loaidvht_id NUMBER;
        v_status_map  NUMBER := 2; -- Mặc định 2: Đã cấp phát (Active)
    BEGIN
        -- 0. [THÊM MỚI] Tra cứu CUMHT_ID (số) từ MA_CUMHT (chuỗi như 'local')
        BEGIN
            SELECT CUMHT_ID INTO v_cumht_id
            FROM CUM_HT
            WHERE MA_CUMHT = P_CLUSTER_ID
              AND ROWNUM = 1;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                -- Cụm không tồn tại trên OneBSS -> bỏ qua
                RETURN;
        END;
        
        -- 1. Nếu API gom được status = active/updating -> Chuyển thành trạng thái (2); khác thì cho (0)
        IF LOWER(P_STATUS) IN ('removed', 'deleting', 'suspended') THEN
            v_status_map := 0; 
        END IF;
        -- 2. TRUY ID DỊCH VỤ dùng v_cumht_id (NUMBER) đã tra cứu ở bước 0
        BEGIN
            SELECT DICHVUHT_ID, LOAIDVHT_ID INTO v_dvht_id, v_loaidvht_id
            FROM DICHVU_HT
            WHERE CUMHT_ID = v_cumht_id   -- [SỬA] dùng v_cumht_id (NUMBER), không dùng TO_NUMBER(P_CLUSTER_ID)
              AND (TEN_DICHVU = P_SERVICE_NAME OR MA_DICHVU = P_ORDER_CODE)
              AND ROWNUM = 1;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                -- Bỏ qua nếu Dịch vụ do Ops khai nội bộ IDG mà không có thông tin Đặt Hàng từ OneBSS.
                RETURN; 
        END;
        -- 3. Cập nhật Trạng thái và "Mộc thời gian" cho bảng Thông tin: DICHVU_HT
        UPDATE DICHVU_HT
        SET TRANGTHAICC_ID = v_status_map,
            NGAY_CN = SYSDATE 
        WHERE DICHVUHT_ID = v_dvht_id;
        -- 4. Bơm thông số tài nguyên vào đúng bảng Chuyên Biệt Năng Lực (NANGLUC_DVHT) chuẩn theo ERD
        UPDATE NANGLUC_DVHT
        SET SL_CORECPU    = TO_NUMBER(NVL(P_VCPU, '0')),     -- Bẫy NVL chống Invalid Number
            DL_RAM     = TO_NUMBER(NVL(P_VRAM, '0')), 
            DL_STORAGE = TO_NUMBER(NVL(P_VSTORAGE, '0')),
            NGAY_CN    = SYSDATE,
            NGUOI_CN    = 'SYSTEM_SYNC'
        WHERE DICHVUHT_ID = v_dvht_id;
        -- 5. Đóng Log xuống bảng Lịch Sử Vẽ Biểu Đồ (LICHSU_CAPPHAT)
        INSERT INTO LICHSU_CAPPHAT (
            CUMHT_ID,
            LOAIDVHT_ID,
            LOAI_DOITUONG,
            DOITUONG_ID,     
            SL_CORECPU,     
            DL_RAM,
            DL_STORAGE,
            GHICHU,
            --TRANGTHAI,
            NGAY_CP,
            NGUOI_CN,
            NGAY_CN
        ) VALUES (
            v_cumht_id,          -- [SỬA] dùng v_cumht_id (NUMBER), không dùng TO_NUMBER(P_CLUSTER_ID)
            v_loaidvht_id,
            'DICHVU_HT',
            v_dvht_id,
            TO_NUMBER(NVL(P_VCPU, '0')),
            TO_NUMBER(NVL(P_VRAM, '0')),
            TO_NUMBER(NVL(P_VSTORAGE, '0')),
            'Đồng bộ Bước 3: Cập nhật Capacity mới nhất từ IDG backend xả xuống',
            --v_status_map,
            SYSDATE,
            'SYSTEM_SYNC',
            SYSDATE
        );
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END SP_CAPNHAT_DICHVU_CAPPAT;
    
    PROCEDURE SP_KIEMTRA_DICHVU_DAGO (
        P_CLUSTER_ID   IN VARCHAR2,   -- MA_CUMHT (vd: 'local') - KHÔNG phải số CUMHT_ID
        P_RANCHER_CODE IN VARCHAR2
    ) IS
        V_CUMHT_ID NUMBER;  -- [THÊM MỚI] Tra cứu CUMHT_ID thực từ MA_CUMHT
        
        -- [SỬA] Cursor dùng V_CUMHT_ID (NUMBER) thay vì P_CLUSTER_ID (VARCHAR2)
        CURSOR c_deleted_instances IS
            SELECT DICHVUHT_ID, LOAIDVHT_ID 
            FROM DICHVU_HT
            WHERE CUMHT_ID = V_CUMHT_ID            -- [SỬA] CUMHT_ID (NUMBER) = V_CUMHT_ID (NUMBER) -> đúng kiểu
              AND NVL(TRANGTHAICC_ID, -1) != 0  
              AND (NGAY_CN IS NULL OR NGAY_CN < SYSDATE - INTERVAL '15' MINUTE);
    BEGIN
        -- [THÊM MỚI] Bước 0: Tra cứu CUMHT_ID từ MA_CUMHT để tránh ORA-01722
        BEGIN
            SELECT CUMHT_ID INTO V_CUMHT_ID
            FROM CUM_HT
            WHERE MA_CUMHT = P_CLUSTER_ID
              AND ROWNUM = 1;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                -- Cụm không tồn tại -> không có gì để dọn dẹp, thoát an toàn
                RETURN;
        END;
        
        -- =========================================================================
        -- PHẦN 1: DỌN DẸP BẢNG LOẠI DỊCH VỤ CUNG CẤP (DICHVU_CUMHT) TỪ BƯỚC 2
        -- =========================================================================
        UPDATE DICHVU_CUMHT
        SET SUDUNG = 0,         -- Đánh dấu Ngừng hỗ trợ/Bị gỡ loại Dịch Vụ
            NGAY_CN = SYSDATE,
            GHICHU = 'Loại Dịch Vụ Cung Cấp này đã bị gỡ khỏi Backend'
        WHERE CUMHT_ID = V_CUMHT_ID    -- [SỬA] dùng V_CUMHT_ID (NUMBER), không dùng P_CLUSTER_ID (VARCHAR2)
          AND NVL(SUDUNG, 1) != 0
          AND (NGAY_CN IS NULL OR NGAY_CN < SYSDATE - INTERVAL '15' MINUTE);
          
        -- =========================================================================
        -- PHẦN 2: DỌN DẸP BẢNG GÓI DỊCH VỤ CẤP PHÁT CHI TIẾT (DICHVU_HT) TỪ BƯỚC 3
        -- =========================================================================
        FOR v_rec IN c_deleted_instances LOOP
            
            -- Chuyển trạng thái = 0
            UPDATE DICHVU_HT
            SET TRANGTHAICC_ID = 0,
                NGAY_CN = SYSDATE,
                GHICHU = 'Hệ thống tự động Thu Hồi gói theo đồng bộ IDG Bước 4'
            WHERE DICHVUHT_ID = v_rec.DICHVUHT_ID;
            -- Giải phóng Năng Lực = 0 cho Cụm
            UPDATE NANGLUC_DVHT
            SET SL_CORECPU = 0,
                DL_RAM = 0,
                DL_STORAGE_CP = 0,
                NGAY_CN = SYSDATE,
                NGUOI_CN = 'SYSTEM_SYNC'
            WHERE DICHVUHT_ID = v_rec.DICHVUHT_ID;
            -- Ghi Log Lịch Sử thu hồi tài nguyên
            INSERT INTO LICHSU_CAPPHAT (
                CUMHT_ID,
                LOAIDVHT_ID,
                LOAI_DOITUONG,
                DOITUONG_ID,       
                SL_CORECPU,        
                DL_RAM,            
                DL_STORAGE,
                NGAY_CP,
                GHICHU,
                NGUOI_CN,
                NGAY_CN
            ) VALUES (
                V_CUMHT_ID,              -- [SỬA] dùng V_CUMHT_ID (NUMBER), không dùng P_CLUSTER_ID (VARCHAR2)
                v_rec.LOAIDVHT_ID,   -- Link loại dịch vụ
                'DICHVU_HT',       -- Label đối tượng
                v_rec.DICHVUHT_ID,
                0,                 -- CPU quay đầu về 0
                0,                 -- RAM quay đầu về 0
                0,                 -- STORAGE quay đầu về 0
                SYSDATE,
                'Đồng bộ Bước 4: Tự động ghi nhận dịch vụ đã bị thu hồi khỏi IDG backend.',
                'SYSTEM_SYNC',
                SYSDATE
            );
        END LOOP;
        
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END SP_KIEMTRA_DICHVU_DAGO;

END PKG_TEST_THUANLN_HCM;