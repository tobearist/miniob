/* Copyright (c) 2021 OceanBase and/or its affiliates. All rights reserved.
miniob is licensed under Mulan PSL v2.
You can use this software according to the terms and conditions of the Mulan PSL v2.
You may obtain a copy of Mulan PSL v2 at:
         http://license.coscl.org.cn/MulanPSL2
THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
See the Mulan PSL v2 for more details. */

#pragma once

#include "sql/stmt/stmt.h"

class Db;

/**
 * @brief ALTER TABLE ADD COLUMN
 */
class AlterTableStmt : public Stmt
{
public:
  AlterTableStmt(const string &table_name, const AttrInfoSqlNode &attr)
      : table_name_(table_name), attr_(attr)
  {}
  virtual ~AlterTableStmt() = default;

  StmtType type() const override { return StmtType::ALTER_TABLE; }

  const string           &table_name() const { return table_name_; }
  const AttrInfoSqlNode  &attribute() const { return attr_; }

  static RC create(Db *db, const AlterTableSqlNode &alter_table, Stmt *&stmt);

private:
  string          table_name_;
  AttrInfoSqlNode attr_;
};
