/* Copyright (c) 2021 OceanBase and/or its affiliates. All rights reserved.
miniob is licensed under Mulan PSL v2.
You can use this software according to the terms and conditions of the Mulan PSL v2.
You may obtain a copy of Mulan PSL v2 at:
         http://license.coscl.org.cn/MulanPSL2
THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
See the Mulan PSL v2 for more details. */

#include "sql/stmt/alter_table_stmt.h"

#include "storage/db/db.h"
#include "storage/table/table.h"

RC AlterTableStmt::create(Db *db, const AlterTableSqlNode &alter_table, Stmt *&stmt)
{
  if (db->find_table(alter_table.relation_name.c_str()) == nullptr) {
    return RC::SCHEMA_TABLE_NOT_EXIST;
  }

  Table *table = db->find_table(alter_table.relation_name.c_str());
  if (table->table_meta().field(alter_table.new_attribute.name.c_str()) != nullptr) {
    return RC::SCHEMA_TABLE_EXIST;
  }

  stmt = new AlterTableStmt(alter_table.relation_name, alter_table.new_attribute);
  return RC::SUCCESS;
}
